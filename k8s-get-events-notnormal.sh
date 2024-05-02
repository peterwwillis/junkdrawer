#!/usr/bin/env sh
# k8s-get-events-notnormal.sh - Get all Kubernetes events not of type 'Normal'

# you might find passing the '-w' and '-n' options useful!
set -eu ; [ "${DEBUG:-0}" = "1" ] && set -x
kubectl get events --field-selector 'type!=Normal' "$@"
