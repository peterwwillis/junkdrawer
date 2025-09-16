#!/usr/bin/env bash
# aws-ec2-instanceconnect-run-ssh.sh - Uses AWS EC2 Instance Connect to run commands on multiple hosts
#
# This script helps you run arbitrary commands on EC2 instances that support Instance Connect.
#
# Since the 'ec2-instance-connect ssh' command does not support SSH options (booooo!)
# there's a second mode here ('-L' option) that will push an SSH public key of
# your choice to the server and then SSH to it (you can pass SSH_OPTS to provide custom
# ssh command options).
#
set -eu
[ "${DEBUG:-0}" = "1" ] && set -x

inst_id_filters="Name=instance-state-name,Values=running"
inst_id_query='Reservations[].Instances[].{ID:InstanceId,VPC:VpcId}'
os_user="root"

_get_cmd_stdin () {
    printf "%s: Getting ssh command from stdin ...\n" "$0" 1>&2
    command="$( cat /dev/stdin )"
    printf "%s\n" "$command"
}

_find_ssh_public_key () {
    # Try to use the specified file or agent, otherwise use default files
    if [ -n "$ssh_public_key_file" ] ; then
        cat "$ssh_public_key_file"
    elif command -v ssh-add >/dev/null 2>&1 ; then
        agent_key="$( ssh-add -L 2>/dev/null | head -1 )"
        if [ -n "$agent_key" ] ; then
            printf "%s\n" "$agent_key"
            return
        fi
    else
        for file in ~/.ssh/id_rsa.pub ~/.ssh/id_ecdsa.pub ~/.ssh/id_ecdsa_sk.pub ~/.ssh/id_ed25519.pub ~/.ssh/id_ed25519_sk.pub ; do
            [ -r "$file" ] && { cat "$file"; return; }
        done
    fi
    echo "$0: ERROR: Could not find an ssh public key" >&2
    exit 1
}

# Get instance ID and VPC of all instances
_get_inst_ids () {
    while read -r id vpc ; do
        inst_ids_a+=("$id")
        vpc_map["$id"]="$vpc"
    done < <(aws ec2 describe-instances --filters "$inst_id_filters" --query "$inst_id_query" --output text)

    if [ -n "$aws_inst_ids" ] ; then
        inst_ids_a=()
        read -r -a inst_ids_a <<< "$aws_inst_ids"
    fi
}

# NOTE: only run after _get_instance_ids
_get_endpoints () {
    for vpc in $(printf '%s\n' "${vpc_map[@]}" | sort -u); do
        endpoints_map["$vpc"]=$(aws ec2 describe-instance-connect-endpoints \
            --filters Name=vpc-id,Values="$vpc" Name=state,Values=create-complete \
            --query 'InstanceConnectEndpoints[*].InstanceConnectEndpointId' \
            --output text)
    done
}

_bigprint () {
    echo "================================================="
    echo "========= $*  ============"
    echo "================================================="
}

_run_cmds_ic_ssh () {
    local command
    if [ ! "${no_command:-0}" = "1" ] ; then
        if [ $# -gt 0 ] ; then
            command="$*"
        else
            command="$( _get_cmd_stdin )"
        fi
    fi
    _get_inst_ids
    for inst_id in "${inst_ids_a[@]}" ; do
        _bigprint "Connecting to instance $inst_id"
        set +e
        if [ -n "${command:-}" ] ; then
            printf "%s\nexit\n" "$command" | \
                aws ec2-instance-connect ssh --instance-id "$inst_id" --os-user "$os_user" --no-cli-pager
        else
            aws ec2-instance-connect ssh --instance-id "$inst_id" --os-user "$os_user" --no-cli-pager
        fi
        ret=$?
        set -e
        if [ $ret -ne 0 ] ; then
            echo "$0: ERROR: SSH did not return success! Returned: $ret" >&2
            failed_insts["$inst_id"]="$ret"
        fi
    done
}

_run_cmds_local_key () {
    local command ssh_public_key proxy_command vpc_id endpoint
    if [ ! "${no_command:-0}" = "1" ] ; then
        if [ $# -gt 0 ] ; then
            command="$*"
        else
            command="$( _get_cmd_stdin )"
        fi
    fi
    ssh_public_key="$( _find_ssh_public_key )"
    if [ -z "$ssh_public_key" ] ; then
        echo "$0: ERROR: No ssh public key detected" >&2
        exit 1
    fi
    _get_inst_ids
    _get_endpoints
    for inst_id in "${inst_ids_a[@]}" ; do
        _bigprint "Sending SSH key to instance $inst_id"
        if aws ec2-instance-connect send-ssh-public-key \
            --instance-id "$inst_id" \
            --instance-os-user "$os_user" \
            --ssh-public-key "$ssh_public_key" \
            --no-cli-pager; then

            vpc_id="${vpc_map[$inst_id]}"
            endpoint_ids="${endpoints_map[$vpc_id]}"
            endpoint=''
            if [ -n "${aws_ec2_ic_endpoint:-}" ]; then
                endpoint="$aws_ec2_ic_endpoint"
            elif [ -n "$endpoint_ids" ]; then
                endpoint="$(printf '%s\n' "$endpoint_ids" | head -n1)"
            fi
            proxy_command="aws ec2-instance-connect open-tunnel --local-port 0 --instance-id %h"
            if [ -n "$endpoint" ] ; then
                proxy_command="$proxy_command --instance-connect-endpoint-id $endpoint"
            fi

            set +e
            _bigprint "Making SSH connection to $inst_id via endpoint '${endpoint:-public}'"
            if [ -n "${command:-}" ] ; then
                ssh ${SSH_OPTS:-} -o ProxyCommand="$proxy_command" "$os_user@$inst_id" <<EOF
$command
exit \$?
EOF
            else
                ssh ${SSH_OPTS:-} -o ProxyCommand="$proxy_command" "$os_user@$inst_id"
            fi
            ret=$?
            set -e
            if [ $ret -ne 0 ] ; then
                echo "$0: ERROR: SSH did not return success! Returned: $ret" >&2
                failed_insts["$inst_id"]="$ret"
            fi
        fi
    done
}

_usage () {
    cat <<EOUSAGE
Usage: $0 [OPTIONS] [COMMAND]

Run a COMMAND on a bunch of EC2 instances using Instance Connect.

This uses AWS's built-in functionality to copy an SSH public key to a
server and drop you into an SSH connection. This way you do not need to
already have your own SSH key on the server in question.

By default, uses a query and filter to look up which EC2 instances to connect to.
You can change the filter (-F) and query (-Q) to control which instances are
looked up. Use the -I option to pass specific instance IDs instead.

Pass the AWS_REGION environment variable to change the region.

If you do not pass a COMMAND, defaults to using the standard-input
to this script as the COMMAND to run. The COMMAND is anything that a
shell can execute. If you pass -N, no COMMAND is needed and interactive
mode is attempted.

If you use -L option, you can pass environment variable SSH_OPTS,
which are more options for the 'ssh' command.

Options:
  -U USER           SSH user to connect as ($os_user)
  -F FILTER         EC2 describe-instances filter ($inst_id_filters)
  -Q QUERY          EC2 describe-instances query ($inst_id_query)
  -I INSTID         Pass specific instance IDs instead of querying
  -L                Use local SSH public key (sets SSH_OPTS)
  -k FILE           Public key file (requires -L)
  -E ENDPOINT       Use given EC2 IC endpoint ID
  -l                List AWS EC2 Instance Connect endpoints
  -i                List AWS EC2 instance IDs
  -N                Do not run a command, try interactive mode instead
  -h                Help
EOUSAGE
    exit 1
}

use_local_key=0 list_aws_ic_e=0 list_aws_instid=0 no_command=0
ssh_public_key_file='' aws_ec2_ic_endpoint='' aws_inst_ids=''
declare -a inst_ids_a=()
declare -A vpc_map=() endpoints_map=() failed_insts=()

while getopts "U:F:Q:I:LliNk:E:h" args ; do
    case $args in
        U)  os_user="$OPTARG" ;;
        F)  inst_id_filters="$OPTARG" ;;
        Q)  inst_id_query="$OPTARG" ;;
        I)  aws_inst_ids="$OPTARG" ;;
        L)  use_local_key=1 ;;
        l)  list_aws_ic_e=1 ;;
        i)  list_aws_instid=1 ;;
        N)  no_command=1 ;;
        k)  ssh_public_key_file="$OPTARG" ;;
        E)  aws_ec2_ic_endpoint="$OPTARG" ;;
        *)  _usage ;;
    esac
done
shift $((OPTIND-1))

if [ $list_aws_ic_e -eq 1 ] ; then
    printf "AWS EC2 instance connect endpoints available:\n"
    aws ec2 describe-instance-connect-endpoints \
        --filters Name=state,Values=create-complete \
        --query "InstanceConnectEndpoints[*].{EndpointID: InstanceConnectEndpointId, Tags: join(', ', Tags[].join('=', [Key, Value]))}" \
        --output table
    exit 0
elif [ $list_aws_instid -eq 1 ] ; then
    aws ec2 describe-instances \
        --filters Name=instance-state-name,Values=running \
        --query 'Reservations[].Instances[].InstanceId' \
        --output text | tr '\t' '\n'
    exit 0
fi

if [ $use_local_key -eq 1 ] ; then
    _run_cmds_local_key "$@"
else
    _run_cmds_ic_ssh "$@"
fi

if [ ${#failed_insts[@]} -gt 0 ] ; then
    echo ""
    echo "ERROR: The following instances returned an error: ${!failed_insts[*]}"
    echo ""
fi
