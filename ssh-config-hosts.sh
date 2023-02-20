#!/usr/bin/env sh
# ssh-config-hosts.sh - Recursively find any 'Host <host>' lines in local ssh configs
# 
# Usage: ssh-config-hosts [FILE]

set -eu
[ "${DEBUG:-0}" = "1" ] && set -x

_read_file_key () {
    key="$1"; shift
    grep -H -i -E "^\s*$key\s" "$@" | cut -d : -f 2- | awk '{print $2}'
}

_recurse_files () {
    for file in "$@" ; do
        _read_file_key "Host" "$file"
        _read_file_key "Include" "$file" \
            | sed -E 's/^[[:space:]]*Include[[:space:]]+//g' \
            | while read -r FILE
        do
            _recurse_files "$FILE"
        done
    done
}

if [ $# -gt 0 ] ; then
    _recurse_files "$@"
else
    _recurse_files ~/.ssh/config
fi
