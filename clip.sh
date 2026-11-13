#!/usr/bin/env sh
set -eu
[ "${DEBUG:-0}" = "1" ] && set -x

if [ -n "${WAYLAND_DISPLAY:-}" ] && command -v wl-copy >/dev/null 2>&1 ; then
    wl-copy
elif command -v pbcopy >/dev/null 2>&1 ; then
    pbcopy
elif command -v xsel >/dev/null 2>&1 ; then
    xsel --clipboard --input
else
    echo "$0: ERROR: No clipboard command found"
    exit 1
fi

