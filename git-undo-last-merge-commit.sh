#!/usr/bin/env sh
set -eu
# - 'ORIG_HEAD' uses the last commit before a 'dangerous' operation
#    like a merge or rebase
# - '--merge' is safer than '--hard' for resolving merge commits
git reset --merge ORIG_HEAD
