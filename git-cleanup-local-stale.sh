#!/usr/bin/env sh
# git-cleanup-local-stale.sh - Remove any stale local and remote Git branches from local repository

[ "${DEBUG:-0}" = "1" ] && set -x
git remote prune origin
git branch -vv | \grep -E '\[origin/[^:]+: gone\]' | sed -e 's/^.//' | awk '{print $1}' | xargs git branch -D
