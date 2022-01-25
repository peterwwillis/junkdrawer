#!/usr/bin/env bash
set -eu
[ "${DEBUG:-0}" = "1" ] && set -x
SD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

[ $# -gt 0 ] || { echo "Usage: $0 ORG TEAM [curl-args ..]" 1>&2 ; exit 1 ; }

org="$1" team="$2" ; shift 2

memburl="$( "$SD"/get-github-team.sh "$org" "$team" | jq -e -r .members_url | sed -e 's/{\/member}//' )";
"$SD"/get-github-restapi.sh "$memburl"
