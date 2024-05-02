#!/usr/bin/env bash
# jenkins-add-credential.sh - Adds a credential to Jenkins credential store via REST API
# 
# Example:
# 
#   $ JENKINS_SERVER_URL=https://foo.com/ \
#       ./add-jenkins-credential.sh easi-github-token <redacted>

#set -Eeuo pipefail
set -eo pipefail
#set -x

# Using jenkins rest API for credentials - https://getintodevops.com/blog/how-to-add-jenkins-credentials-with-curl-or-ansible

function define () { IFS='\n' read -r -d '' ${1} || true; }

function _create_cred_text () {
    define myjson <<EOCCT
json={
    "": "0",
    "credentials": {
        "scope": "GLOBAL",
        "id": "$1",
        "secret": "$2",
        "description": "$1",
        "\$class": "org.jenkinsci.plugins.plaincredentials.impl.StringCredentialsImpl"
    }
}
EOCCT
    echo "$myjson"
}

function _create_cred_user_pass () {
    define myjson <<EOCCT
json={
  "": "0",
  "credentials": {
    "scope": "GLOBAL",
    "id": "$1",
    "username": "$2",
    "password": "$3",
    "description": "$1",
    "\$class": "com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl"
  }
}
EOCCT
    echo "$myjson"
}

function _create_cred_aws () {
    define myjson <<EOCCT
json={
  "": "0",
  "credentials": {
    "scope": "GLOBAL",
    "id": "$1",
    "accessKey": "$2",
    "secretKey": "$3",
    "description": "$1",
    "\$class": "com.cloudbees.jenkins.plugins.awscredentials.AWSCredentialsImpl"
  }
}
EOCCT
    echo "$myjson"
}

function _send_cred () {
    echo "Creating '$1' ..."
    ./jenkins-curl-wrapper.sh \
        -XPOST \
        --data-urlencode "$2" \
        ${JENKINS_SERVER_URL}/credentials/store/system/domain/_/createCredentials
}

function _usage () {
    cat <<EOUSAGE
Usage: $0 TYPE [OPTIONS ..]

Creates a credential on a remote Jenkins manager.
Pass OPTIONS to the TYPE to specify the arguments for the credentials.

Valid types:
  text
  user_pass

'text' type options:
    NAME                    The credential ID
    SECRET                  The credential secret text

'user_pass' type options:
    NAME                    The credential ID
    USERNAME                The credential username
    PASSWORD                The credential password

'aws' type options:
    NAME                    The credential ID
    ACCESSKEY               The credential AWS access key
    SECRETKET               The credential AWS secret key
EOUSAGE
    exit 1
}

if [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ -z "$1" ] ; then
    _usage
fi

if [ -z "${JENKINS_SERVER_URL}" ] ; then
    echo "Error: set JENKINS_SERVER_URL environment variable"; exit 1
fi

TYPE="$1"
shift

NAME="$1"
JSON="$(_create_cred_$TYPE "$@")"
_send_cred "$NAME" "$JSON"
