#!/usr/bin/env sh
# git-cleanup-local-stale.sh - Remove any stale local and remote Git branches from local repository

[ "${DEBUG:-0}" = "1" ] && set -x
git remote prune origin

git branch -vv | \grep -E '\[origin/[^:]+: gone\]' | sed -e 's/^.//' | awk '{print $1}' | while read branch; do
    worktree_path=$(git worktree list --porcelain | awk -v branch="$branch" '
        /^worktree / { path = substr($0, 10) }
        /^branch / && $2 == "refs/heads/" branch { print path; exit }
    ')
    
    if [ -n "$worktree_path" ]; then
        if git -C "$worktree_path" diff --quiet && git -C "$worktree_path" diff --cached --quiet; then
            echo "Removing clean worktree: $worktree_path"
            git worktree remove "$worktree_path"
        else
            echo "Skipping worktree with changes: $worktree_path"
            continue
        fi
    fi
    
    git branch -D "$branch"
done
