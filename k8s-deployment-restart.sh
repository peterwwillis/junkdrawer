#!/usr/bin/env sh
set -eu
[ "${DEBUG:-0}" = "1" ] && set -x

if [ $# -lt 1 ] ; then
    echo "Usage: $0 DEPLOYMENT [KUBECTL_ARGS ..]"
    exit 1
fi

dply="$1"; shift
kubectl rollout restart "deployments/$dply" "$@"
