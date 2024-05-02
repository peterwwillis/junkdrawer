#!/usr/bin/env sh
# git-clean.sh - Interactively remove unchecked-in Git working directory files

# Note: this command appears to work on a relative path; it does not
# automatically start from the root of the git repo.
git clean -i -d -x
