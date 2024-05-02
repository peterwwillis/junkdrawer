#!/usr/bin/env bash
# wget-mirror.sh - Use Wget to create a mirror of a website

set -eu
[ "${DEBUG:-0}" = "1" ] && set -x

declare -a WGET_HEADERS=() WGET_ARGS=()
WGET_USER_AGENT="Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:92.0) Gecko/20100101 Firefox/92.0"
WGET_DOMAINS="myexampledomain.atlassian.net,atlassian.net,aid-frontend.prod.atl-paas.net,metal.prod.atl-paas.net,atl-paas.net"
WGET_RECURSION_DEPTH="5"
WGET_WAIT="1"
#WGET_LIMIT="1000k"
#WGET_LOG="wget.log"
WGET_NO_CLOBBER=0
WGET_CONVERT_LINKS=1

[ -n "$CONFLUENCE_USER" ] && [ -n "$CONFLUENCE_PASS" ] && \
    WGET_ARGS+=(--header "Authorization: Basic $(printf "%s" "$CONFLUENCE_USER:$CONFLUENCE_PASS" | base64)")

if [ ${#WGET_HEADERS[*]} -gt 0 ] ; then
    for i in "${WGET_HEADERS[@]}" ; do
        WGET_ARGS+=(--header "$i")
    done
fi

[ -n "${WGET_USER_AGENT:-}" ]       && WGET_ARGS+=("--user-agent=$WGET_USER_AGENT")
[ -n "${WGET_DOMAINS:-}" ]          && WGET_ARGS+=("--domains=$WGET_DOMAINS")
[ -n "${WGET_RECURSION_DEPTH:-}" ]  && WGET_ARGS+=("--level=$WGET_RECURSION_DEPTH")
[ -n "${WGET_WAIT:-}" ]             && WGET_ARGS+=("--wait=$WGET_WAIT")
[ -n "${WGET_LIMIT:-}" ]            && WGET_ARGS+=("--limit-rate=$WGET_LIMIT")
[ -n "${WGET_LOG:-}" ]              && WGET_ARGS+=("--output-file=$WGET_LOG")
[ "${WGET_NO_CLOBBER:-0}" = "1" ]   && WGET_ARGS+=("--no-clobber")
[ "${WGET_CONVERT_LINKS:-0}" = "1" ] && WGET_ARGS+=("--convert-links")

if [ $# -lt 1 ] ; then
    echo "Usage: $0 URL [..]"
    exit 1
fi
declare -a URLS=("$@")

wget \
     --recursive \
     --page-requisites \
     --adjust-extension \
     --span-hosts \
     --restrict-file-names=windows \
     --no-parent \
     --random-wait \
     --execute robots=off \
     "${WGET_ARGS[@]}" \
         "${URLS[@]}"

