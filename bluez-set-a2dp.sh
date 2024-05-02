#!/usr/bin/env bash
# bluez-set-a2dp.sh - Try to force-enable A2DP mode for Bluetooth devices

set -u
[ "${DEBUG:-0}" = "1" ] && set -x

_restart_bluetooth () {
    sudo systemctl stop bluetooth
    sleep 1
    killall pulseaudio
    sleep 1
    sudo systemctl start bluetooth
    sleep 1
}

_set_a2dp () {
    read -r -a cards <<< "$(pactl list cards  | grep Name: | awk '{print $2}' | grep bluez)"
    read -r -a sinks <<< "$(pactl list cards | grep "Part of profile" | cut -d : -f 2- | sed -e 's/\s//g; s/,/\n/g')"

    count=0
    for card in "${cards[@]}" ; do
        for sink in "${sinks[@]}" ; do
            if [ "$sink" = "a2dp_sink" ] ; then
                pactl set-card-profile "$card" "$sink"
                count=$((count+1))
            fi
        done
    done
    if [ $count -eq 0 ] ; then
        echo "$0: Error: no cards/sinks found"
        exit 1
    fi
}

_list_bluetooth_devices () {
    bluetoothctl devices
}
_connect_bluetooth () {
    connectto="$1"
    devices="$(bluetoothctl devices)"
    while read -r device ; do
        devid="$(printf "%s\n" "$device" | cut -d ' ' -f 2)"
        devname="$(printf "%s\n" "$device" | cut -d ' ' -f 3-)"
        echo "bt device: $devname ($devid)"
        if [ "$devid" = "$connectto" ] || [ "$devname" = "$connectto" ] ; then
            bluetoothctl connect "$connectto"
        fi
    done <<<"$devices"
}

_usage () {
    cat <<EOUSAGE
Usage: $0 [OPTIONS]

Options:
  -c DEVICE             Connect to Bluetooth device
  -l                    List bluetooth devices
  -R                    Killall pulseaudio daemons, stop bluetooth, start bluetooth
  -h                    This screen
  -v                    Enable trace mode
EOUSAGE
    exit 1
}

BT_RESTART=0 BT_CONNECT=''
while getopts "hRlc:v" args ; do
      case "$args" in
          h)  _usage ;;
          v)  DEBUG=1; set -x ;;
          c)  BT_CONNECT="$OPTARG" ;;
          R)  BT_RESTART=1 ;;
          l)  BT_LIST_DEVICE=1 ;;
          *)  echo "$0: Error: invalid option '$args'" ; exit 1 ;;
      esac
done
shift $((OPTIND-1))

[ "${BT_RESTART:-0}" = "1" ] && _restart_bluetooth
[ -n "$BT_CONNECT" ] &&  _connect_bluetooth "$BT_CONNECT"

if [ "${BT_LIST_DEVICE:-0}" = "1" ] ; then
        _list_bluetooth_devices
else
    _set_a2dp
fi
