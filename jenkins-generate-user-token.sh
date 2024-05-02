#!/usr/bin/env bash
# jenkins-generate-user-token.sh - Generates a Jenkins user token

set -eo pipefail

function _usage () {
    cat <<EOUSAGE
Usage: $0 [OPTIONS] [TOKEN_NAME]

Generates a new Jenkins user token.

Unfortunate chicken-egg: you can't log in with your SSO credentials to use this
script; you must already have a token to use this to generate tokens.

EOUSAGE
    exit 1
}

if [ "$1" = "-h" ] || [ "$1" = "--help" ] ; then
    _usage
fi
if [ -z "$JENKINS_SERVER_URL" ] ; then
    echo "Error: set JENKINS_SERVER_URL environment variable"; exit 1
fi

# Optional token name
if [ -n "$1" ] ; then
    OPTS="--data newTokenName=$1"
    shift
else
    # Apparently we still have to give this even if we have no value
    OPTS="--data newTokenName="
fi

exec ./jenkins-curl-wrapper.sh $OPTS "$JENKINS_SERVER_URL/me/descriptorByName/jenkins.security.ApiTokenProperty/generateNewToken"
