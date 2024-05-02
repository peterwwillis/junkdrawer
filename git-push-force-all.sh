#!/usr/bin/env sh
# git-push-force-all.sh - Force-push a Git repository (with tags)

set -eu
git push --force --tags origin 'refs/heads/*'
