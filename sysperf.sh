#!/usr/bin/env sh
set -eu

OS="$(uname -s)"

# Show what files this process is writing to
_diagnose_Linux_io_filesbypid () {
    for pid in "$@" ; do
        lsof -b -w -n -p "$pid" \
            | grep -E '^([^[:space:]]+)[[:space:]]+([^[:space:]]+)[[:space:]]+([^[:space:]]+)[[:space:]]+([[:digit:]]+u?w?)[[:space:]]+' \
            | awk '{$1=$2=$3=$4=$5=$6=$7=$8=""; print $0}' \
            | sed -E 's/^[[:space:]]+//g' | grep -v -E '^[[:space:]]*$' \
            | sort | uniq -c | sort -g
    done
}
_diagnose_Linux_io () {
    pidstat -d
    iotop-c -b -n 2 -d 15 -a -k -c -e -o
    sudo fatrace -f W -s 15 | cut -d' ' -f2- | sort | uniq -c | sort -nr

    #sudo sysdig -c topfiles_bytes # interactive
}

# Notes:
#  - Use `about:debugging#/runtime/this-firefox` in firefox to find extension IDS.
#    Can track down a chatty extension i/o that way

_diagnose_"$OS"_io
