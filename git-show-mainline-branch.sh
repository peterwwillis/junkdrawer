#!/usr/bin/env sh
set -eu
[ "${DEBUG:-0}" = "1" ] && set -x
_git_remote_HEAD () {
    git branch -rl | grep -oE "HEAD -> (.*)" | sed -E "s/^.*HEAD -> //"
}
_git_remote_HEAD_branch () {
    _git_remote_HEAD | cut -d / -f 2-
}
_git_local_tracking_branch () {
    head="$(_git_remote_HEAD)"
    git branch -vv | tr '*' ' ' | grep -E "\[$head\]" | awk '{print $1}'
}
if [ "${1:-}" = "-r" ] ; then
    _git_remote_HEAD_branch
else
    _git_local_tracking_branch
fi
