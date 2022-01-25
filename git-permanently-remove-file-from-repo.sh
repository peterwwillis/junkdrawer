#!/usr/bin/env sh

remove_file_from_git () {
    local file="$1"; shift
    git filter-branch --force --index-filter \
      "git rm --cached --ignore-unmatch '$file'" \
      --prune-empty --tag-name-filter cat -- --all
}

if [ $# -lt 1 ] ; then
    echo "Usage: $0 FILE [..]"
    echo ""
    echo "Permanently removes FILE from the current directory's git repo"
    exit 1
fi

for file in "$@" ; do
    remove_file_from_git "$file"
done

