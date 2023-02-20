#!/usr/bin/env sh
set -eu ; [ "${DEBUG:-0}" = "1" ] && set -x
kubectl get secrets --field-selector type=Opaque "$@"
