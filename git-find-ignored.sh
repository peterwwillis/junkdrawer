#!/usr/bin/env sh
# git-find-ignored.sh - Show all the files in the current Git repo that are being ignored by .gitignore

# git status --ignored .

git clean -ndX | sed -e 's/^Would remove //g'
