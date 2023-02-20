#!/usr/bin/env sh
# you might find passing the '-w' and '-n' options useful!
set -eu ; [ "${DEBUG:-0}" = "1" ] && set -x
kubectl get events --field-selector 'type!=Normal' "$@"
