#!/bin/sh
[ $# -lt 1 ] && git grep --help
git rev-list --all | xargs -n10 git grep "$@" | cat
