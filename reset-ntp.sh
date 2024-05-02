#!/usr/bin/env sh
# reset-ntp.sh - Update the time on a box using ntp

export PATH="$PATH:/sbin:/usr/sbin:/usr/local/sbin"

sudo service ntp stop
sudo ntpdate "$NTPDOMAIN"
sudo service ntp start
