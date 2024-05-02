#!/usr/bin/env bash
# ubuntu-18.04-setup-dnsmasq.sh - Set up DNSMASQ on Ubuntu 18.04

set -euo pipefail

# Some more useful configuration tips at http://www.g-loaded.eu/2010/09/18/caching-nameserver-using-dnsmasq/

SUDO=sudo

$SUDO apt-get update
$SUDO apt-get install -y dnsmasq

# If you don't disable systemd, you may need one of these fixes: https://askubuntu.com/questions/907246/how-to-disable-systemd-resolved-in-ubuntu/
$SUDO systemctl disable systemd-resolved
$SUDO systemctl stop systemd-resolved

# If NetworkManager was installed, try to force 'default' dns.
# Alternately you could configure NetworkManager to start dnsmasq: https://askubuntu.com/questions/1029882/how-can-i-set-up-local-wildcard-127-0-0-1-domain-resolution-on-18-04
if systemctl status NetworkManager 2>/dev/null 1>/dev/null ; then
    if [ -e /etc/NetworkManager/NetworkManager.conf ] ; then
        if grep -q dns= /etc/NetworkManager/NetworkManager.conf ; then
            sed -i -e 's/dns=.*/dns=default/g'/etc/NetworkManager/NetworkManager.conf
        else
            sed -i -e 's/[main].*/[main]\ndns=default\n/' /etc/NetworkManager/NetworkManager.conf
        fi
    fi
    $SUDO systemctl restart NetworkManager
fi

if [ ! -e /etc/resolv.dnsmasq ] ; then
    $SUDO cp -f /etc/resolv.conf /etc/resolv.dnsmasq
    $SUDO /bin/sh -c 'echo "resolv-file /etc/resolv.dnsmasq" > /etc/dnsmasq.d/resolv-file'
    $SUDO /bin/sh -c 'echo "nameserver 127.0.0.1" > /etc/resolv.conf'
fi

$SUDO systemctl enable dnsmasq.service
$SUDO systemctl restart dnsmasq.service
