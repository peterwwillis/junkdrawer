#!/usr/bin/env sh
# list-dupe-files.sh - Find and list duplicate files
#
# Pass this script one or more files or directories, and it will print out
# the files that are duplicates. Uses md5sum for comparison.

if [ $# -lt 1 ] ; then
    echo "Usage: $0 FILE|DIR [..]"
    exit 1
fi

find "$@" -type f -exec md5sum {} \; | sort | awk '$1 in a{if(a[$1])print a[$1];a[$1]=""; print; next} {a[$1]=$0}'
