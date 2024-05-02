#!/usr/bin/env sh
# git-list-repo-files.sh - List all files checked into a git repository

if [ "$1" = "-h" -o "$1" = "--help" ] ; then
    echo "Usage: $0 [OPTIONS] [REF]"
    echo ""
    echo "Options:"
    echo "    -h,--help                 This help menu"
    echo ""
    echo "Lists all files checked into a git repository. REF defaults to the current HEAD reference (usually the current branch)."
    exit 1
fi

if [ $# -lt 1 ] ; then
    REF="$(git rev-parse --abbrev-ref HEAD)"
    if [ -z "$REF" ] ; then
        echo "$0: Error: could not get current HEAD abbreviated reference name"
        exit 1
    fi

else
    REF="$1"
    shift
fi

git ls-tree --full-tree -r --name-only "$REF"
