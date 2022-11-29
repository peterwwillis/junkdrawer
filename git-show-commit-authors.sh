#!/usr/bin/env sh
set -eu
git log --pretty=full | grep  -E '(Author|Commit): (.*)$' | sed 's/Author: //g' | sed 's/Commit: //g' | sort -u
