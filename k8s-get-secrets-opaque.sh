#!/usr/bin/env sh
# k8s-get-secrets-opaque.sh - Get any 'Opaque' type k8s secrets

set -eu ; [ "${DEBUG:-0}" = "1" ] && set -x
kubectl get secrets --field-selector type=Opaque "$@"
