#!/usr/bin/env sh
# git-grep-entire-repo-history.sh - Grep the entire history of a Git repository

[ $# -lt 1 ] && git grep --help
git rev-list --all | xargs -n10 git grep "$@" | cat
