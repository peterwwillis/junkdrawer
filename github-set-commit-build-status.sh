#!/usr/bin/env bash
# github-set-commit-build-status.sh - Set commit build status for a GitHub commit

set -eo pipefail
[ x"$DEBUG" = "x1" ] && set -x

BUILD_URL="http://about:blank"
BUILD_CONTEXT="continuous-integration/jenkins"
if [ $# -lt 3 ] ; then
    echo "Usage: $0 GITHUB_ORG REPO_NAME GIT_COMMIT [BUILD_CONTEXT] [BUILD_URL]"
    echo ""
    echo "Defaults:"
    echo "  BUILD_CONTEXT=$BUILD_CONTEXT"
    echo "  BUILD_URL=$BUILD_URL"
    exit 1
fi

ORG_NAME="$1"; shift
REPO_NAME="$1"; shift
GIT_COMMIT="$1"; shift
if [ $# -gt 0 ] ; then BUILD_CONTEXT="$1"; shift ; fi
if [ $# -gt 0 ] ; then BUILD_URL="$1"; shift ; fi

if [ ! -n "$GITHUB_TOKEN" ] ; then
    echo "$0: Error: you must set GITHUB_TOKEN environment variable" ; exit 1
fi

DATA=$(cat << EOF
{
  "state":       "success",
  "context":     "$BUILD_CONTEXT",
  "description": "Manually passing the commit status",
  "target_url":  "$BUILD_URL"
}
EOF
)
URL="https://api.github.com/repos/$ORG_NAME/$REPO_NAME/statuses/$GIT_COMMIT?access_token=$GITHUB_TOKEN"

curl \
  "$URL" \
  -H "Content-Type: application/json" \
  -X POST \
  -d "$DATA"
