#!/usr/bin/env sh
# k8s-get-secret-values.sh - Output kubernetes secret keys and values in plaintext

set -eu
[ "${DEBUG:-0}" = "1" ] && set -x

[ $# -gt 0 ] || { echo "Usage: $0 SECRET [ARGS ..]" ; exit 1 ; }

kubectl get \
    secret \
    "$@" \
    -o go-template='{{range $k,$v := .data}}{{printf "%s=" $k}}{{if not $v}}{{$v}}{{else}}{{$v | base64decode}}{{end}}{{"\n"}}{{end}}'
