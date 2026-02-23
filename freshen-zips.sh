#!/usr/bin/env bash
# freshen-zips.sh - freshen files in a zip file
#
# Pass zip files as arguments. Each will be run with the '--freshen'
# option, which updates files that already exist in the zip file,
# if the local files on disk have been updated.
#
# This is effectively a really simple backup program.
#
set -u
[ "${DEBUG:-0}" = "1" ] && set -x

for f in "$@" ; do
    [ -f "$f" ] || continue
    zip -9 -f "$f"
    ret=$?
    # return status 12: zip has nothing to do
    if [ $ret -eq 0 ] || [ $ret -eq 12 ] ; then
        continue
    else
        exit $ret
    fi
done

exit 0
