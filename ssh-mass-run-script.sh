#!/usr/bin/env bash
# ssh-mass-run-script.sh - send a script to a lot of hosts and then execute it on them
# Note: this script does not fail on error, in order to work on as many hosts as possible.

set -e -o pipefail

# Run this many copies at once; later, run script on this many hosts at once.
PARALLEL_PROCS="20"

_usage () {
    echo "Usage: $0 SCRIPT HOSTLIST"
    echo ""
    echo "Send and execute SCRIPT on each host in file HOSTLIST."
    echo ""
    echo "Each entry in HOSTLIST is passed as the target to SCP and SSH, so it can"
    echo "include a username, like 'USER@HOST'."
    echo ""
    echo "If HOSTLIST is '-', reads list from standard input."
    exit 1
}

if [ $# -lt 2 ] ; then
    _usage
fi

SCRIPT="$1"; shift
SCRIPT_FN="$(basename "$SCRIPT")"
HOSTLIST="$1"; shift

if [ "$HOSTLIST" = "-" ] ; then
    # stdin
    HOSTLIST=""
elif [ ! -r "$HOSTLIST" ] ; then
    echo "$0: Error: cannot read hostlist file '$HOSTLIST'" ; exit 1
fi

if [ ! -r "$SCRIPT" ] ; then
    echo "$0: Error: cannot read script '$SCRIPT'" ; exit 1
fi

set +e

# What the following command does:
#  - send the hostlist to xargs
#  - xargs takes one argument of input per command to run
#  - xargs will replace '{}' with the argument
#  - xargs will run up to $PARALLEL_PROCS commands at a time
#  - the command is a /bin/sh one-liner
#    - run scp with CheckHostIP and StrictHostKeyChecking disabled, so a redeployed host doesn't break the command
#    - if the scp succeeds, continue
#    - run ssh with CheckHostIP and StrictHostKeyChecking disabled, so a redeployed host doesn't break the command
#      - ssh into the argument ( "{}" )
#        - set the script as executable
#        - run the script, assuming it was copied into the current directory
#        - always return true, because if the command fails, and ssh fails, xargs will die early

echo "$0: Copying '$SCRIPT' to hosts in '$HOSTLIST' and executing them ..."
sleep 2
cat "$HOSTLIST" | \
    xargs \
      -I {} \
      -n 1 \
      -P "$PARALLEL_PROCS" \
      /bin/sh -c "
        echo \"Copying '$SCRIPT' to '{}:$SCRIPT_FN' ...\" && \
        scp -o CheckHostIP=no -o StrictHostKeyChecking=no \"$SCRIPT\" {}:\"$SCRIPT_FN\" && \
        echo \"Running './$SCRIPT_FN' on host '{}' ...\" && \
        ssh -o CheckHostIP=no -o StrictHostKeyChecking=no {} \"chmod u+x ./$SCRIPT_FN ; ./$SCRIPT_FN\" \
        ; true
      "
echo "$0: Done copying to hosts"

