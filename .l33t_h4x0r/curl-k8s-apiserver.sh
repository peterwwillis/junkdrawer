#!/usr/bin/env sh
set -eu
[ "${DEBUG:-0}" = "1" ] && set -x

if [ -d /run/secrets/kubernetes.io/serviceaccount ] ; then
    secret_path="/run/secrets/kubernetes.io/serviceaccount/token"
elif [ -d /var/run/secrets/kubernetes.io/serviceaccount ] ; then
    secret_path="/var/run/secrets/kubernetes.io/serviceaccount/token"
else
    echo "$0: ERROR: Could not detect service account token; pass as K8S_TOKEN"
fi

if [ -e "$secret_path/ca.crt" ] ; then
    export SSL_CERT_FILE="$secret_path/ca.crt"
fi

K8S_TOKEN="${K8S_TOKEN:-$(cat "$secret_path")}"

KUBERNETES_SERVICE_HOST="${KUBERNETES_SERVICE_HOST:-kubernetes.default.svc}"
KUBERNETES_SERVICE_PORT="${KUBERNETES_SERVICE_PORT:-443}"

K8S_NS="${K8S_NS:-default}"
K8S_SERVICE="${K8S_SERVICE:-pods}"

if [ -z "${SSL_CERT_FILE:-}" ] ; then
    CURL_ARGS="${CURL_ARGS:-} -k"
fi

curl $CURL_ARGS \
    -X GET \
    -H "Authorization: Bearer ${K8S_TOKEN}" \
    "https://${KUBERNETES_SERVICE_HOST}:${KUBERNETES_SERVICE_PORT}/api/v1/namespaces/${K8S_NS}/${K8S_SERVICE}"
