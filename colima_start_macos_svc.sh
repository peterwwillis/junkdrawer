#!/usr/bin/env bash
# colima_start_macos_svc.sh
set -u
[ "${DEBUG:-0}" = "1" ] && set -x

COLIMA_INSTANCE_NAME="ai-agent-1"

# To install on MacOS:
#
#     echo "H4sIANqfl2kCA5WRQU/DMAyF7/sVIffVcEMoKyrbkCYqVrHuwAllbdRFpE3lOBv796Tr0Do0IZGT5Tx/78kWj1+1YTuFTttmwu+iW85UU9hSN9WEr/Pn8T1/jEfiZrac5u/ZnLVGO2LZ+ildTBkfAyRtaxTALJ+xLF2schYYAPNXzviWqH0A2O/3kexUUWHrTuggQ9sqpEMaYOMwEJVU8mDT0y/ihG6pC4pHLDzxqQ5xKjfKCOjKvukIQ9w40CPvFEaOJFJhja6lgNPneTx4VyjrBCtfq4bckCQR5akeksE7BGMLaWCjGzjyP3qDyG1/ecAAcjR8801CqZXl0InQKxiIXpRqE6N36i/RimRTSizniBYzSdsrW4Cd7LJWlykV4pVV/PCWnv5Fs57ONAH9fQQcrxePvgENcB7zVAIAAA==" \
#       | base64 -d | gzip -d -c > com.user.startcolima.plist
#
#     sudo ln -sf $(readlink -f com.user.startcolima.plist) /Library/LaunchDaemons/com.user.startcolima.plist
#
#     # validate syntax
#     plutil -lint /Library/LaunchDaemons/com.user.startcolima.plist
#
#     # NOTE: required!
#     sudo chown root:wheel /Library/LaunchDaemons/com.user.startcolima.plist
#     sudo chmod 0644 /Library/LaunchDaemons/com.user.startcolima.plist
#     
#     sudo launchctl load /Library/LaunchDaemons/com.user.startcolima.plist


_log () { printf "%s: %s: %s\n" "$(date "+%Y-%m-%d_%H:%M:%S")" "$0" "$*" ; }

# Load user's bash profile for paths, etc
. /Users/admin/.bash_profile


# Allow for a delay to ensure system services are up
sleep 10

# Start Colima in the background with output to a log file
_log "Starting colima..."
colima start "$COLIMA_INSTANCE_NAME"

sleep 1

while true; do

    cmd_out="$(colima status "$COLIMA_INSTANCE_NAME" 2>&1)"
    ret=$?
    if [ $ret -ne 0 ] ; then
        _log "ERROR: colima instance '$COLIMA_INSTANCE_NAME' not running; output:"
        _log "$cmd_out"
        _log "Attempting to start colima..."
        colima start "$COLIMA_INSTANCE_NAME"
    fi

    sleep 10

done
