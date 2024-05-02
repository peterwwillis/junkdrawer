#!/usr/bin/env bash
# github-get-restapi.sh - Curl the GitHub API

set -eu
[ "${DEBUG:-0}" = "1" ] && set -x
SD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

[ $# -gt 0 ] || { echo "Usage: $0 URI [curl-args ..]" 1>&2 ; exit 1 ; }

path="$1" ; shift

url="https://api.github.com/$path"
if expr "$path" : "https\?://" >/dev/null ; then
    url="$path"
fi

[ -n "${GITHUB_TOKEN:-}" ] || \
    { echo "$0: Error: please set environment variable GITHUB_TOKEN" 1>&2 ; exit 1 ; }

curl -fsSL -H "Authorization: bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github.v3+json" "$url" "$@"
