#!/usr/bin/env bash
# colima_start_macos_svc.sh - A Bash wrapper to start Colima at boot time on MacOS
#
# If you want to start a colima VM on MacOS at boot time (NOT at login time),
# it's a bit complicated. You apparently can't configure the launch daemon
# to assume a user's permissions (anymore). But you can use 'sudo' to run a
# script as a user; it just won't be a "true user session", which luckily
# we don't need to run colima.
#
# Instructions:
#
#   1. Install colima as a normal user and create a VM
#
#   1. Set the COLIMA_INSTANCE_NAME (the VM name you created, e.g. 'default')
#      and COLIMA_SUDO_USER in the script below.
#
#   2. Extract the launchctl config as follows:
#
#          $ echo "H4sIANqfl2kCA5WRQU/DMAyF7/sVIffVcEMoKyrbkCYqVrHuwAllbdRFpE3lOBv796Tr0Do0IZGT5Tx/78kWj1+1YTuFTttmwu+iW85UU9hSN9WEr/Pn8T1/jEfiZrac5u/ZnLVGO2LZ+ildTBkfAyRtaxTALJ+xLF2schYYAPNXzviWqH0A2O/3kexUUWHrTuggQ9sqpEMaYOMwEJVU8mDT0y/ihG6pC4pHLDzxqQ5xKjfKCOjKvukIQ9w40CPvFEaOJFJhja6lgNPneTx4VyjrBCtfq4bckCQR5akeksE7BGMLaWCjGzjyP3qDyG1/ecAAcjR8801CqZXl0InQKxiIXpRqE6N36i/RimRTSizniBYzSdsrW4Cd7LJWlykV4pVV/PCWnv5Fs57ONAH9fQQcrxePvgENcB7zVAIAAA==" \
#            | base64 -d | gzip -d -c > com.user.startcolima.plist
#
#          $ sudo ln -sf $(readlink -f com.user.startcolima.plist) /Library/LaunchDaemons/com.user.startcolima.plist
#
#   3. Open the file and edit it to point to the full path of this script
#
#   4. Validate the syntax, just in case:
#
#          $ plutil -lint /Library/LaunchDaemons/com.user.startcolima.plist
#
#   5. Set the correct ownership and permissions for the launchctl config:
#
#          $ sudo chown root:wheel /Library/LaunchDaemons/com.user.startcolima.plist
#          $ sudo chmod 0644 /Library/LaunchDaemons/com.user.startcolima.plist
#     
#   6. Load the service (this will start it immediately)
#     
#          $ sudo launchctl load /Library/LaunchDaemons/com.user.startcolima.plist
#
#   7. `tail -f /var/log/start_colima.*` to watch logs and check that it started
#
set -u
[ "${DEBUG:-0}" = "1" ] && set -x


# Set these variables before starting the script
# 
COLIMA_INSTANCE_NAME="ai-agent-1"
COLIMA_SUDO_USER="admin"


###################################################################################################
###################################################################################################


SCRIPT="${BASH_SOURCE[0]}"

_log () { printf "[%s] %s: %s\n" "$(date "+%Y-%m-%dT%H:%M:%S%z")" "$(basename "$SCRIPT")" "$*" ; }

# A bunch of portable-ish ways to get home directory
_gethome () {
    _home="$(getent passwd "$(id -un)" 2>/dev/null | cut -d : -f 6)"
    _home="${_home:-$(id -P 2>/dev/null | cut -d : -f 9)}"
    _home="${_home:-$(perl -le'@_=getpwnam(getlogin);print $_[7]')}"
    _home="${_home:-$(python -c 'import os,pwd; print( pwd.getpwnam(os.getlogin()).pw_dir )')}"
    printf "%s\n" "$_home"
}

if [ "$(id -u)" = "0" ] && [ -n "${COLIMA_SUDO_USER:-}" ] ; then
    _log "Root user detected, and COLIMA_SUDO_USER '$COLIMA_SUDO_USER' passed; rerunning with sudo..."
    cd /
    exec sudo -i -H -n -u "$COLIMA_SUDO_USER" "$SCRIPT" "$@"
fi


export HOME="${HOME:-$(_gethome)}"
if [ -d "$HOME" ] ; then
    if ! cd "$HOME" ; then
        _log "ERROR: Failed to cd to '$HOME'; exiting"
        exit 1
    fi
fi

# Load user's bash profile for paths, etc.
# Technically this is wrong as this should only be loaded for an interactive shell.
# So before this happens, we will set a variable the user can check for in their init
# scripts.
export COLIMA_START_MACOS_SVC=1 COLIMA_INSTANCE_NAME COLIMA_SUDO_USER

# Undo the 'set -u' from earlier, in case their init script is buggy
set +u

# Load the interactive login init scripts
if [ -r .bash_profile ] ; then
    . ./.bash_profile
elif [ -r .bash_login ] ; then
    . ./.bash_login
elif [ -r .profile ] ; then
    . ./.profile
fi
# This is for interactive shells that are *not* login shells. Since this script will never
# be interactive, technically both these sections are wrong
if [ -r .bashrc ] ; then
    . ./.bashrc
fi

# Re-enable 'set -u' for safety
set -u

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
