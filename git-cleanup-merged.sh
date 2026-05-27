#!/usr/bin/env bash
# git-cleanup-merged.sh - Clean up git branches that were already merged into main
set -eu

# Get current branch
BRANCH="$(git rev-parse --abbrev-ref HEAD)"

# 1. Try to find the specific upstream branch this branch tracks
# 2. If no upstream, detect the remote's default branch
# 3. If that fails, fallback to 'main'
UPSTREAM_FULL="$(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null)"

_usage () {
    cat <<EOUSAGE
Usage: $0 [OPTIONS]

Find out if current Git branch has been merged into upstream tracking branch (or default branch).

Options:
  -d                Delete branch if already merged
EOUSAGE
    exit 1
}

if [ "${1:-}" = "-h" ] ; then
    _usage
fi

if [ -n "$UPSTREAM_FULL" ]; then
    UPSTREAM="$UPSTREAM_FULL"
    echo "📍 Tracking Upstream: $UPSTREAM"
else
    DEFAULT_BRANCH="$(git remote show origin 2>/dev/null | awk '/HEAD branch/ {print $NF}')"
    UPSTREAM="origin/${DEFAULT_BRANCH:-main}"
    echo "⚠️  No upstream set for '$BRANCH'. Comparing to default: $UPSTREAM"
fi

# Sync with remote
echo "🔄 Fetching latest from remote..."
git fetch origin --quiet

MERGED=false

# Check 1: History check
if git merge-base --is-ancestor "$BRANCH" "$UPSTREAM" 2>/dev/null; then
    echo "✅ MERGED (History match)"
    MERGED=true

# Check 2: Content/Squash check
elif [[ -z $(git cherry "$UPSTREAM" "$BRANCH" 2>/dev/null | grep "^+") ]]; then
    echo "✅ MERGED (Content/Squash match)"
    MERGED=true

else
    echo "❌ NOT MERGED into $UPSTREAM"
fi

# Deletion logic (triggered if -d flag is present)
if [[ "${1:-}" == "-d" ]] && [ "$MERGED" = true ]; then
    echo "🗑️  Deleting local branch '$BRANCH'..."
    # Switch to the upstream branch (removing 'origin/' prefix) before deleting
    TARGET_LOCAL="${UPSTREAM#origin/}"
    git checkout "$TARGET_LOCAL" --quiet
    git branch -D "$BRANCH"
fi
