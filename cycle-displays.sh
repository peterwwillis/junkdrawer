#!/usr/bin/env bash
# cycle=displays.sh - use xrandr (X11) to cycle through monitors to mirror or extend
#
set -u
[ "${DEBUG:-0}" = "1" ] && set -x

#declare -a displays=( $(xrandr --listmonitors | grep -E '^[[:space:]]*[[:digit:]]+:' | cut -d : -f 2 | awk '{print $1}' | sed -E 's/[+*]//g' | xargs) )
declare -a connected_displays=( $(xrandr | grep ' connected' | awk '{print $1}' | xargs) )

declare -a connected_resolution=()
for display in "${connected_displays[@]}" ; do
    resolution="$(xrandr | grep ' connected' | sed -E 's/connected |primary |same-as //g' | grep -o -E "^$display [0-9]+x[0-9]+[^[:space:]]*")"
    connected_resolution+=("$resolution")
done

echo -n "Connected displays: " ;  printf "%s\n" "${connected_displays[*]:0:2}"

if [ -z "${connected_resolution[1]:-}" ]; then
    echo "Primary not on; enabling secondary, disabling primary"
    xrandr --output "$INTERNAL" --off --output "$EXTERNAL" --auto

elif [ -n "${connected_displays[1]:-}" ] \
     && [ $(printf "%s\n" "${connected_resolution[@]:0:2}" | grep -c "+0+0") -eq 2 ]
then
    echo "Primary and secondary are mirrored; extending secondary"
    xrandr --output "${connected_displays[0]}" --auto --output "${connected_displays[1]}" --auto --right-of "${connected_displays[0]}"

else
    echo "Mirroring primary and secondary"
    xrandr --output "${connected_displays[0]}" --auto --output "${connected_displays[1]}" --auto --same-as "${connected_displays[0]}"

fi
