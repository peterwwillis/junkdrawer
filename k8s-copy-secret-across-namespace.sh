#!/usr/bin/env sh
# k8s-copy-secret-across-namespace.sh - Copy a Kubernetes secret into a new namespace

set -eu
[ "${DEBUG:-0}" = "1" ] && set -x

_usage () { echo "Usage: $0 SECRET OLDNS NEWNS [OLDCONTEXT NEWCONTEXT]" ; exit 1 ; }


oldcontext="" newcontext=""
[ $# -gt 2 ] || _usage
secretname="$1" oldns="$2" newns="$3"
shift 3
if [ $# -eq 2 ] ; then
    oldcontext="--context=$1" newcontext="--context=$2"
elif [ $# -gt 0 ] ; then
    _usage
fi

kubectl get secret "$secretname" -n "$oldns" -o yaml $oldcontext \
    | grep -v '^\s*namespace:\s' \
    | kubectl apply -f - -n "$newns" $newcontext
