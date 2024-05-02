#!/usr/bin/env sh
# git-fix-commit-author.sh - Rewrite Git history to correct the wrong commit author details

set -e -u

read -r -p "Old e-mail? " OLD_EMAIL
read -r -p "Correct name? " CORRECT_NAME
read -r -p "Correct e-mail? " CORRECT_EMAIL

git filter-branch --env-filter "
if [ \"\$GIT_COMMITTER_EMAIL\" = \"$OLD_EMAIL\" ] ; then
    export GIT_COMMITTER_NAME=\"$CORRECT_NAME\"
    export GIT_COMMITTER_EMAIL=\"$CORRECT_EMAIL\"
fi
if [ \"\$GIT_AUTHOR_EMAIL\" = \"$OLD_EMAIL\" ] ; then
    export GIT_AUTHOR_NAME=\"$CORRECT_NAME\"
    export GIT_AUTHOR_EMAIL=\"$CORRECT_EMAIL\"
fi
" --tag-name-filter cat -f -- --all
