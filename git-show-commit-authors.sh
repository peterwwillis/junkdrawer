#!/usr/bin/env sh
# git-show-commit-authors.sh - List all of the commit authors in a Git repository

set -eu
git log --pretty=full | grep  -E '(Author|Commit): (.*)$' | sed 's/Author: //g' | sed 's/Commit: //g' | sort -u
