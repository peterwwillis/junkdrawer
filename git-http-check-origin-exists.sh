#!/usr/bin/env sh
# git-http-check-origin-exists.sh - In case you want to use 'curl' to see if an HTTP(s) Git repo actually exists or not

# Usage:    git-http-check-origin-exists.sh https://somedomain.com/somedir/somerepo.git

set -eu
[ "${DEBUG:-0}" = "1" ] && set -x

# Should return 0 on success, non-zero on error
exec curl -nfsSL "$1/info/refs?service=git-receive-pack" -o /dev/null
