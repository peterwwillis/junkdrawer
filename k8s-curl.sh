#!/usr/bin/env sh
# k8s-curl.sh - Curl the K8s API, from within a K8s pod
set -eu
[ "${DEBUG:-0}" = "1" ] && set -x

_die () { printf "$0: Error: %s\n" "$*" 1>&2 ; exit 1 ; }

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] ; then
    cat <<EOUSAGE
Usage: $0 [OPTIONS] [URL]

Runs 'curl' against a K8s API server URL, passing any other options after that to curl.
Attempts to detect the default CA cert file and bearer token in a pod.

Valid URL formats:
    https://kubernetes.default.svc.cluster.local    (default)
    http://kubernetes.default.svc.cluster.local
    https://kubernetes.default.svc.cluster.local/something
    http://kubernetes.default.svc.cluster.local/something
    /something
    something

Options:

  --cacert FILE         A file containing the CA cert of the K8s API server.
  --bearerfile FILE     A file containing the K8s Bearer token.

Environment variables:

  K8S_CACERT            A file containing the CA cert of the K8s API server.
  K8S_BEARER_FILE       A file containing the K8s Bearer token.
  K8S_BEARER            The K8s bearer token itself.
EOUSAGE
    exit 1
fi

K8S_CACERT="${K8S_CACERT:-/var/run/secrets/kubernetes.io/serviceaccount/ca.crt}"
if [ "${1:-}" = "--cacert" ] ; then
    K8S_CACERT="$2"; shift 2
fi
if [ ! -e "$K8S_CACERT" ] ; then
    _die "Could not find CA cert '$K8S_CACERT'"
fi

K8S_BEARER_FILE="${K8S_BEARER_FILE:-/var/run/secrets/kubernetes.io/serviceaccount/token}"
if [ "${1:-}" = "--bearerfile" ] ; then
    K8S_BEARER_FILE="$2" ; shift 2
fi
K8S_BEARER="${K8S_BEARER:-$(cat "$K8S_BEARER_FILE")}"
if [ -z "${K8S_BEARER:-}" ] ; then
    if [ ! -e "$K8S_BEARER_FILE" ] ; then
        _die "Could not find k8s bearer token file '$K8S_BEARER_FILE'"
    fi
fi

_default_url="https://kubernetes.default.svc.cluster.local"
K8S_URL="${K8S_URL:-${1:-}}"
url_proto="${K8S_URL#http}"
if [ ! "${url_proto:0:4}" = "s://" ] && [ ! "${url_proto:0:3}" = "://" ] ; then
    if [ ! "${K8S_URL:0:1}" = "/" ] ; then
        K8S_URL="/$K8S_URL"
    fi
    K8S_URL="${_default_url}${K8S_URL}"
fi


curl \
    --cacert "$K8S_CACERT" \
    -H  "Authorization: Bearer $K8S_BEARER" \
    "$K8S_URL" \
    "$@"
echo
