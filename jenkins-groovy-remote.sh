#!/bin/sh
set -e
[ -n "$DEBUG" ] && set -x

_get_crumb () {
    curl -s -u "${JENKINS_USER}:${JENKINS_PASS}" "${JENKINS_URL}"'/crumbIssuer/api/xml?xpath=concat(//crumbRequestField,":",//crumb)'
}

if [ $# -lt 2 ] ; then
    echo "Usage: $0 JENKINS_URL GROOVY_FILE"
    echo ""
    echo "Runs a GROOVY_FILE on a JENKINS_URL server, first by grabbing a CSRF token, then by submitting the GROOVY_FILE"
    echo "to JENKINS_URL/scripText, and returning the output."
    echo ""
    echo "If GROOVY_FILE is '-', curl should read the file from standard input."
    echo "The environment variables JENKINS_USER and JENKINS_PASS must be set in advance."
    exit 1
fi

set -u

JENKINS_URL="$1"; shift
GROOVY_FILE="$1" ; shift

JENKINS_CRUMB=$(_get_crumb)

curl \
  -s \
  -H "${JENKINS_CRUMB}" \
  -u "${JENKINS_USER}:${JENKINS_PASS}" \
  -XPOST \
  --data-urlencode "script@$GROOVY_FILE" \
  ${JENKINS_URL}/scriptText
