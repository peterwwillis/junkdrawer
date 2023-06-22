#!/usr/bin/env sh
# envsubst.sh - POSIX-compatible version of envsubst
# 
# Feed it text on standard input, and it prints the text to standard output,
# replacing ${FOO} or $FOO in the text with the value of the variable.
# 
# This is *very* slow, but it's about as fast as I can get it using just
# POSIX shell stuff (sed/awk would be faster). Use GNU envsubst for speed.
# 
# Since this is a shell script, it conflates shell variables with
# environment variables. You can load this script into your shell
# and it will use those variables specific to your shell session:
#     cat Sample.txt | . ./envsubst.sh
# 
# Or you can call this script as an external executable and it will
# use only exported variables:
#     cat Sample.txt | ./envsubst.sh
# 

[ "${DEBUG:-0}" = "1" ] && set -x

while IFS= read -r foo ; do
    # Loop until the line no longer has any $FOO or ${FOO} variables
    while : ; do
        # Match on either $FOO or ${FOO}
        match="$( expr "$foo" : '.*${\{0,\}\([a-zA-Z0-9_]*\)}\{0,\}' )"
        [ -n "$match" ] || break
        eval new="\${$match:-}"
        prefix="${foo%\$\{$match\}*}"
        suffix="${foo#*\$\{$match\}}"
        if [ ! "$suffix" = "$foo" ] ; then
            # If suffix had a match, replace the line
            foo="${prefix}${new}${suffix}"
        else
            # Otherwise try the replacement without the ${FOO} form
            prefix="${foo%\$$match*}"
            suffix="${foo#*\$$match}"
            if [ ! "$suffix" = "$foo" ] ; then
                foo="${prefix}${new}${suffix}"
            else
                break
            fi
        fi
    done
    printf "%s\n" "$foo"
done
