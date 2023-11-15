#!/usr/bin/env sh
set -eu
[ "${DEBUG:-0}" = "1" ] && set -x

_urlencode_str () { # Usage: _urlencode_str STRING
  local encoded="" pos c o
  for (( pos=0 ; pos<${#1} ; pos++ )); do
     c="${1:$pos:1}" ; case "$c" in
        [-_.~a-zA-Z0-9])    o="$c" ;;
        *)                  printf -v o '%%%02X' "'$c"
     esac ; encoded+="$o"
  done ; echo "${encoded}"
}
if [ $# -gt 0 ] ; then
    _urlencode_str "$*"
fi
