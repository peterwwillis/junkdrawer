#!/usr/bin/env sh
[ "${DEBUG:-0}" = "1" ] && set -x
git remote prune origin
git branch -vv | \grep -E '\[origin/[^:]+: gone\]' | sed -e 's/^.//' | awk '{print $1}' | xargs git branch -D
