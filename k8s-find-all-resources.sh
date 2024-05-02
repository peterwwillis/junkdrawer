#!/usr/bin/env sh
# k8s-find-all-resources.sh - Find all Kubernetes resources

set -eu ; [ "${DEBUG:-0}" = "1" ] && set -x
K8S_NS="${K8S_NS:-default}"
[ -z "${1:-}" ] || K8S_NS="$1"
kubectl api-resources --verbs=list --namespaced -o name | xargs -n 1 kubectl get --show-kind --ignore-not-found -o name -n "$K8S_NS"
