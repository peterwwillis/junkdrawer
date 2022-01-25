#!/usr/bin/env bash
# Takes a groovy file, replaces some variables, and executes it on a remote Jenkins instance.
# 
# Sample groovy file:
#   print "ls -la".execute().getText()

#set -Eeuo pipefail
set -eo pipefail

function _run_groovy () {
    GROOVY_FILE="$1"
    if [ ! -r "$GROOVY_FILE" ] ; then
        echo "Error: cannot read file '$GROOVY_FILE'"
        exit 1
    fi

    define mygroovy < $GROOVY_FILE
    # Here we do something arguably very stupid: replace '%%VAR%%' with the
    # value of the environment variable $VAR.
    while [[ $mygroovy =~ ("%%"([[:alnum:]_]+)"%%") ]]; do 
        val=${!BASH_REMATCH[2]}
        if [ ! -n "$val" ] ; then
            echo "ERROR: groovy expected environment variable '${BASH_REMATCH[1]}' but it is not set"
            exit 1
        fi
        mygroovy=${mygroovy//${BASH_REMATCH[1]}/${!BASH_REMATCH[2]}}
    done

    ./jenkins-curl-wrapper.sh \
        -XPOST \
        --data-urlencode "script@$GROOVY_FILE" \
        ${JENKINS_SERVER_URL}/scriptText
}

function _usage () {
    cat <<EOUSAGE
Usage: $0 GROOVY_FILE [..]

Executes a GROOVY_FILE on Jenkins via script console.

If the groovy file contains text like '%%SOMETHING%%', it will be replaced by
the value of an environment variable SOMETHING.
EOUSAGE
    exit 1
}

if [ $# -lt 1 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ] ; then
    _usage
fi

if [ -z "$JENKINS_SERVER_URL" ] ; then
    echo "Error: set JENKINS_SERVER_URL environment variable"; exit 1
fi

for arg in "$@" ; do
    _run_groovy "$arg"
done
