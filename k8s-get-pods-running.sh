#!/usr/bin/env sh
set -eu
[ "${DEBUG:-0}" = "1" ] && set -x
kubectl get pods --field-selector=status.phase==Running "$@"
