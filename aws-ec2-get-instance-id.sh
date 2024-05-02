#!/usr/bin/env bash
# aws-ec2-get-instance-id.sh - Get the Instance ID of running AWS EC2 instances

set -e -o pipefail
[ -n "${DEBUG:-}" ] && set -x

declare -a DI_ARGS_FILTERS=("Name=instance-state-name,Values=running")

function _debug () {
    if [ -n "${DEBUG:-}" ] ; then echo "$0: DEBUG: $@" 1>&2 ; fi
}
function _usage () {
    echo "Usage: $0 OPTIONS"
    echo ""
    echo "Only returns Instance IDs for running instances."
    echo ""
    echo "Options:"
    echo "  -t NAME=VALUE                   Filter by tag NAME and VALUE"
    exit 1
}

JQ_FILTER=".Reservations[].Instances[].InstanceId"

set_tag=0
while getopts "t:h" args ; do
    case $args in
        t)
            IFS='=' read -a strs <<< "$OPTARG"
            _debug "getopts: tag name ${strs[0]} value ${strs[1]}"
            set_tag=1
            DI_ARGS_FILTERS+=("Name=tag:${strs[0]},Values=${strs[1]}")
            ;;
        h)
            _usage
            ;;
        \?)
            _debug "unknown $arg - $OPTARG" ;;
        *)
            _debug "something else $arg - $OPTARG" ;;
    esac
done

aws --output=json ec2 describe-instances --filters "${DI_ARGS_FILTERS[@]}" \
    | jq -r "$JQ_FILTER"
