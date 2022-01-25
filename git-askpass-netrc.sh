#!/bin/sh
# This is mostly unnecessary right now. It was written with the idea that maybe
# one could use a fake username and then substitute it later with a new username
# and a specific personal access token.
# 
# I think the solution is to turn this into a 'credential helper' which can
# take different arguments and actually return both a username and password.
set -x
echo "$@" >&2
url="${1#*'}"
url="${url%%'*}"
login_machine="${url#https://}"
login="${login_machine%%@*}"
machine="${login_machine#*@}"
while read -r line ; do
    found_pass="${line##machine*[\t ]$machine[\t ]*login*[\t ]$login[\t ]*password*[\t ]}"
    [ ! "$line" = "$found_pass" ] && echo "$found_pass" && break
done < ~/.netrc
