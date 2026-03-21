#!/usr/bin/env sh
if [ $# -gt 0 ] ; then
    for i in "$@" ; do
        yq -P < "$i"
    done
else
    yq -P
fi
