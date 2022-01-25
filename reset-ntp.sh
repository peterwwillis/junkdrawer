#!/usr/bin/env sh

export PATH="$PATH:/sbin:/usr/sbin:/usr/local/sbin"

sudo service ntp stop
sudo ntpdate "$NTPDOMAIN"
sudo service ntp start
