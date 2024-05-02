#!/usr/bin/env sh
# k8s-get-pods-running.sh - Get running K8s pods

set -eu
[ "${DEBUG:-0}" = "1" ] && set -x
kubectl get pods --field-selector=status.phase==Running "$@"
