#!/bin/bash
set -e -o pipefail
[ -n "${DEBUG:-}" ] && set -x

function _debug () {
    if [ -n "${DEBUG:-}" ] ; then echo "$0: DEBUG: $@" 1>&2 ; fi
}
function _usage () {
    echo "Usage: $0 OPTIONS"
    echo ""
    echo "Only returns IPs for running instances."
    exit 1
}

#JQ_FILTER=".DBInstances[].Endpoint.Address"
JQ_FILTER=".[].Endpoint.Address"

set_tag=0
while getopts "h" args ; do
    case $args in
        h)
            _usage
            ;;
        \?)
            _debug "unknown $arg - $OPTARG" ;;
        *)
            _debug "something else $arg - $OPTARG" ;;
    esac
done

aws --output=json rds describe-db-instances --query 'DBInstances[?DBInstanceStatus==`available`]' \
    | jq -r "$JQ_FILTER"
