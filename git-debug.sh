#!/usr/bin/env sh
# git-debug.sh - Wrapper around Git to output more debug output
GIT_TRACE=1 GIT_CURL_VERBOSE=1 GIT_SSH_COMMAND="ssh -vvv" git "$@"
