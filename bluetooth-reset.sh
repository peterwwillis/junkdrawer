#!/usr/bin/env sh
# bluetooth-reset.sh - Linux bluetooth needs a kick in the pants every time I connect my headset :(

_system_ctl () {	# _system_ctl SERVICE COMMAND
    if    command -v rc-service 2>/dev/null 1>&2    ; then  sudo rc-service $1 $2
    elif  command -v systemctl 2>/dev/null 1>&2     ; then  sudo systemctl $2 $1
    fi         }

_system_ctl bluetooth stop
sleep 1
rfkill block bluetooth
sleep 1
rfkill unblock bluetooth
sleep 1
_system_ctl bluetooth start
bluetoothctl power on
