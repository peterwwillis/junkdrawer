#!/usr/bin/env bash
# Disable runtime autosuspend for all USB HID input devices (keyboards, mice, touchpads).
# This script writes to the sysfs power‑control files for any USB device that has an
# associated input interface. It uses sudo for the writes, so the script can be run
# as a normal user.

set -euo pipefail

write_power_file() {
    local file="$1"
    local value="$2"
    # Use sudo tee to avoid redirection problems with sudo.
    if [[ -e "$file" ]]; then
        echo "$value" | sudo tee "$file" > /dev/null
    fi
}

# Iterate over every USB device under /sys/bus/usb/devices.
for dev in /sys/bus/usb/devices/*; do
    [[ -d "$dev" ]] || continue
    # Look for an "input" subdirectory (indicates a HID input interface).
    if find "$dev" -maxdepth 2 -type d -name input -print -quit >/dev/null 2>&1; then
        write_power_file "$dev/power/control" "on"
        write_power_file "$dev/power/autosuspend_delay_ms" "-1"
    fi
done

echo "USB input devices have been forced to stay on (autosuspend disabled)."
