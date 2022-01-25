#!/usr/bin/env bash
# Loads Jenkins authentication information and runs curl, passing in command-line arguments.
# Re-use this to call curl on Jenkins servers.
# 
# By default gets and inserts a CSRF crumb in header.
# Pass in '-XGET' or '-XPOST' followed by the rest of your arguments, depending
# on the API calls you're making.
# 
#set -Eeuo pipefail
set -eo pipefail
[ -n "$DEBUG" ] && set -x

function define () { IFS='\n' read -r -d '' ${1} || true; }
function _get_crumb () {
    curl -s -u "${JENKINS_USER}:${JENKINS_TOKEN}" "${JENKINS_SERVER_URL}"'/crumbIssuer/api/xml?xpath=concat(//crumbRequestField,":",//crumb)'
}
function _usage () {
    cat <<EOUSAGE
Usage: $0 CURL_ARGUMENTS [..]

Loads jenkins authentication information and runs curl with arguments provided
on the command-line.

Requires the following environment variables or files:

 JENKINS_USER, $HOME/.jenkins-user                   Jenkins user to login with
 JENKINS_TOKEN, $HOME/.jenkins-token              Jenkins API token or TOKEN
 JENKINS_SERVER_URL, $HOME/.jenkins-url          Base Jenkins url for CSRF crumb

Note that you still need to pass at least a full URL for curl to get as a command-line
argument. Example:

  $0 -XPOST --data-urlencode "script@foo.groovy" http://localhost:8080/scriptText
EOUSAGE
    exit 1
}

if [ -z "$JENKINS_USER" ] && [ -r $HOME/.jenkins-user ] ; then
    JENKINS_USER="$(cat $HOME/.jenkins-user)"
fi
if [ -z "$JENKINS_TOKEN" ] && [ -r $HOME/.jenkins-token ] ; then
    JENKINS_TOKEN="$(cat $HOME/.jenkins-token)"
fi
if [ -z "$JENKINS_SERVER_URL" ] && [ -r $HOME/.jenkins-url ] ; then
    JENKINS_SERVER_URL="$(cat $HOME/.jenkins-url)"
fi
if [ -z "${JENKINS_USER}" ] || [ -z "$JENKINS_TOKEN" ] ; then
    echo "Error: set JENKINS_USER and JENKINS_TOKEN environment variables"
    exit 1
fi
if [ -z "$JENKINS_SERVER_URL" ] ; then
    echo "Error: set JENKINS_SERVER_URL environment variable"
    exit 1
fi

if [ $# -lt 1 ] ; then
    _usage
fi

JENKINS_CRUMB=$(_get_crumb)
set +e
curl \
  -s -H "${JENKINS_CRUMB}" \
  -u "${JENKINS_USER}:${JENKINS_TOKEN}" \
  "$@"
RET=$?
if [ $RET -ne 0 ] ; then
    echo "$0: Error: curl returned an error; set DEBUG=1 for more information"
    exit $RET
fi

