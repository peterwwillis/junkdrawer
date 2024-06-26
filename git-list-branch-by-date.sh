#!/usr/bin/env sh
# git-list-branch-by-date.sh - List Git branches by date of last commit

#for k in `git branch | sed s/^..//`; do printf "%s\t\t%s\n" "$(git log -1 --pretty=format:"%Cgreen%ci %Cblue%cr%Creset" $k --)" "$k" ; done | sort

git for-each-ref --sort='-authordate:iso8601' --format=' %(authordate:relative)%09%(refname:short)' refs/heads
