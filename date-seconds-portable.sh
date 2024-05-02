#!/usr/bin/env sh
# date-seconds-portable.sh - A portable implementation of 'date' output, given SECONDS

set -eu
[ "${DEBUG:-0}" = "1" ] && set -x

_date_fmt_portable () { # Usage: _date_fmt_portable SECONDS
    newtime="$(( $(date +%s) + ${1:-0} ))"
    if [ "$(uname -s)" = "Darwin" ] ; then
        date -u -r "$newtime" +"%Y-%m-%dT%H:%M:%S.000Z"
    else
        date -u -d "@$newtime" +"%Y-%m-%dT%H:%M:%S.000Z"
    fi
}
_date_fmt_portable "$@"
