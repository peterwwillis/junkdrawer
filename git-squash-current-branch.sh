#!/usr/bin/env sh
# git-squash-current-branch.sh - Squash your current branch's commits, based on MAINBRANCH
# 
# From https://stackoverflow.com/a/25357146/3760330

set -eu
[ "${DEBUG:-0}" = "1" ] && set -x

if [ $# -lt 1 ] ; then
    echo "Usage: $0 MAINBRANCH"
    exit 1
fi

mainbranch="$1"

git reset --soft $(git merge-base "$mainbranch" HEAD)
git commit
