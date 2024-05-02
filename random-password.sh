#!/usr/bin/env sh
# random-password.sh - Generate a random password

set -eu
[ "${DEBUG:-0}" = "1" ] && set -x
cat /dev/urandom | LC_ALL=C tr -dc 'a-zA-Z0-9-_\$' | fold -w 20 | sed 1q
