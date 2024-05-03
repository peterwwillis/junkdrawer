#!/usr/bin/env bash
# k8s-diff-secret.sh - A simple k8s secret differ
# 
# Use this script to either diff the names of secrets between two namespaces,
# or to diff the values of two secrets (which may be in different namespaces).
# 
# For a more complex/complete/parallel diff tool, see k8s-diff-secret-by-ns.sh

set -eu
[ "${DEBUG:-0}" = "1" ] && set -x

_diff_two_secrets () {
    local secret1="${1#*/}" secret2="${2#*/}" ns1="${1%%/*}" ns2="${2%%/*}"
    local tmp1 tmp2
    local -a kctl_args=(kubectl get secret -o go-template='{{range $k,$v := .data}}{{printf "%s=%s" $k $v}}{{"\n"}}{{end}}')
    local -a secret1_args=("${kctl_args[@]}")
    local -a secret2_args=("${kctl_args[@]}")
    if [ -n "${ns1:-}" ] && [ ! "$ns1" = "$secret1" ] ; then
        secret1_args+=(-n "$ns1")
    fi
    if [ -n "${ns2:-}" ] && [ ! "$ns2" = "$secret2" ] ; then
        secret2_args+=(-n "$ns2")
    fi
    secret1_args+=("$secret1")
    secret2_args+=("$secret2")
    tmp1="$( mktemp -t "${secret1//[^a-zA-Z0-9]/-}" )"
    tmp2="$( mktemp -t "${secret2//[^a-zA-Z0-9]/-}.XXXXXX" )"
    "${secret1_args[@]}" > "$tmp1"
    "${secret2_args[@]}" > "$tmp2"
    diff -Naur "$tmp1" "$tmp2"
    rm -f "$tmp1" "$tmp2"
}


_diff_two_namespaces () {
    local ns1="$1" ns2="$2"
    tmp1="$( mktemp "$ns1".XXXXXX )" tmp2="$( mktemp "$ns2".XXXXXX )"
    kubectl -n "$ns1" get secret --no-headers=true -o wide | awk '{print $1}' | sort > "$tmp1"
    kubectl -n "$ns2" get secret --no-headers=true -o wide | awk '{print $1}' | sort > "$tmp2"
    diff -Naur "$tmp1" "$tmp2"
    rm -f "$tmp1" "$tmp2"
}

_usage () {
    cat <<EOUSAGE
Usage: $(basename "$0") [OPTIONS] COMMAND [ARGS ..]

Commands:
  ns ONE TWO                    Diff the secrets of namespaces ONE and TWO
  secret [NS/]ONE [NS/]TWO      Diff the secrets ONE and TWO. Optionally specify
                                the namespace NS of each secret.

Options:
  -h                            This help screen
EOUSAGE
    exit 1
}

_run_usage=0
while getopts "hHv" arg ; do
    case "$arg" in
        h)          _run_usage=1 ;;
        *)        _die "Unknown argument '$arg'" ;;
    esac
done
shift $((OPTIND-1))

if [ $_run_usage -eq 1 ] || [ $# -lt 1 ] ; then
    _usage
else
    cmd="$1"; shift
    if [ "$cmd" = "ns" ] ; then
        _diff_two_namespaces "$@"
    elif [ "$cmd" = "secret" ] ; then
        _diff_two_secrets "$@"
    else
        echo "$(basename "$0"): Error: Command '$cmd' invalid"
        _usage
    fi
fi
