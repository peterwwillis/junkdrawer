#!/usr/bin/env sh
# envsubst.sh - POSIX-compatible version of envsubst
# 
# Feed it text on standard input, and it replaces ${FOO} in the text with
# the value of $FOO in the output.

set -u
[ "${DEBUG:-0}" = "1" ] && set -x

while IFS= read -r foo ; do
    while : ; do
        m=1  match="$(expr "$foo" : '.*${\([a-zA-Z0-9_]*\)}')"
        if   [ -z "$match" ]
        then m=2  match="$(expr "$foo" : '.*$\([a-zA-Z0-9_]*\)')"
        fi
        [ -n "$match" ] || break
        eval new="\${$match:-}"
        if   [ $m -eq 1 ]
        then foo="${foo%\$\{$match\}*}${new}${foo#*\$\{$match\}}"
        else foo="${foo%\$$match*}${new}${foo#*\$$match}"
        fi
    done
    printf "%s\n" "$foo"
done
