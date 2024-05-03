#!/usr/bin/env bash
# k8s-diff-secrets.sh - Diff Kubernetes secrets
# 
# This script gives you multiple ways to diff the secrets (names and/or values)
# of Kubernetes secrets.
# 
# To optimize for speed, secret values are not retrieved for diff if a secret
# does not exist in a namespace. Secret retrieval is parallelized with xargs.

set -u
[ "${DEBUG:-0}" = "1" ] && set -x

SCRIPT="$(basename "${BASH_SOURCE[0]}")"

PARALLEL_LIMIT="${PARALLEL_LIMIT:-20}"


_cleanup () {
    ret=$?
    rm -f "${tmp1:-}" "${tmp2:-}"
    exit $ret
}
trap _cleanup EXIT TERM INT HUP ABRT QUIT


##############################################################################

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
    tmp1="$( mktemp -t "$ns1".XXXXXX )" tmp2="$( mktemp -t "$ns2".XXXXXX )"
    kubectl -n "$ns1" get secret --no-headers=true -o wide | awk '{print $1}' | sort > "$tmp1"
    kubectl -n "$ns2" get secret --no-headers=true -o wide | awk '{print $1}' | sort > "$tmp2"
    diff -Naur "$tmp1" "$tmp2"
    rm -f "$tmp1" "$tmp2"
}


###################################################################################

_get_secret () {
    _ns="$1" _secret="$2" _file="$3"
    if ! kubectl -n "$_ns" get secret "$_secret" \
        -o go-template='{{range $k,$v := .data}}{{printf "%s=%s" $k $v}}{{"\n"}}{{end}}' \
        2>/dev/null >"$_file"
    then
        echo "# not found: namespace $_ns secret $_secret"
        return 1
    fi
    return 0
}

_cmd_diff_k8s_secrets () {
    ns1="$1" ns2="$2" ; shift 2
    for d in "$@" ; do
        printf "%s\n" "$d"
    done \
        | xargs -P"$PARALLEL_LIMIT" -n1 "${BASH_SOURCE[0]}" "diff_k8s_secret" "$ns1" "$ns2"
}

_cmd_diff_k8s_secret () {
    local ns1="$1" ns2="$2" secret="$3"
    local tmp1 tmp2 dodiff
    tmp1="$(mktemp -t "$ns1.$secret.XXXXXX")"
    tmp2="$(mktemp -t "$ns2.$secret.XXXXXX")"
    dodiff=1
    _get_secret "$ns1" "$secret" "$tmp1" || dodiff=0
    _get_secret "$ns2" "$secret" "$tmp2" || dodiff=0
    if [ $dodiff -eq 1 ] ; then
        bn1="$(basename "$tmp1")" bn2="$(basename "$tmp2")"
        if ! diff -Naur "$tmp1" "$tmp2" ; then
            echo "# secret $bn1 != $bn2"
        else
            echo "# secret $bn1 == $bn2"
        fi
    fi
    rm -f "$tmp1" "$tmp2"
}

_cmd_diff_ns_values () {
    local ns1="$1" ns2="$2" ; shift 2
    local found
    local -a secrets1=( $(kubectl -n "$ns1" get secret --no-headers=true | awk '{print $1}') )
    local -a secrets2=( $(kubectl -n "$ns2" get secret --no-headers=true | awk '{print $1}') )
    local -a not_in_s1=() not_in_s2=() to_diff=()

    for secret1 in "${secrets1[@]}" ; do
        found=0
        for secret2 in "${secrets2[@]}" ; do
            if [ "$secret1" = "$secret2" ] ; then
                to_diff+=("$secret1")
                found=1
                break
            fi
        done
        [ $found -eq 1 ] || not_in_s2+=("$secret1")
    done
    for secret2 in "${secrets2[@]}" ; do
        found=0
        for secret1 in "${secrets1[@]}" ; do
            if [ "$secret2" = "$secret1" ] ; then
                to_diff+=("$secret2")
                found=1
                break
            fi
        done
        [ $found -eq 1 ] || not_in_s1+=("$secret2")
    done

    for i in "${not_in_s1[@]}" ; do
        echo "# not found: namespace $ns1 secret $i"
    done
    for i in "${not_in_s2[@]}" ; do
        echo "# not found: namespace $ns1 secret $i"
    done

    to_diff_sort_uniq=( $(printf "%s\n" "${to_diff[@]}" | sort | uniq) )
    _cmd_diff_k8s_secrets "$ns1" "$ns2" "${to_diff_sort_uniq[@]}"
}

_usage () {
    cat <<EOUSAGE
Usage: $SCRIPT COMMAND [..]

Diff k8s secrets between two namespaces

Commands:

  ns_names NAMESPACE1 NAMESPACE2
                        Diff the names only of secrets in two different namespaces.

  ns_values NAMESPACE1 NAMESPACE2
                        Diff both the names and the values of all the secrets in
                        two different namespaces. Missing names show up as comments
                        to avoid having to get secrets we know will only result
                        in an empty diff.

  secret [NAMESPACE/]SECRET1 [NAMESPACE/]SECRET2
                        Diff two secrets. You can optionally prefix the secret name
                        with a namespace.

Environment variables:

  PARALLEL_ARGS[=20]    Determines the maximum number of 'kubectl get secret'
                        to run in parallel.

EOUSAGE
    exit 1
}


#################################################################

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
    if [ "$cmd" = "ns_names" ] ; then
        _diff_two_namespaces "$@"
    elif [ "$cmd" = "secret" ] ; then
        _diff_two_secrets "$@"
    elif [ "$cmd" = "ns_values" ] ; then
        _cmd_diff_ns_values "$@"

    # internal functions used by _parallel / xargs
    elif [ "$cmd" = "diff_k8s_secrets" ] ; then
        _cmd_diff_k8s_secrets "$@"
    elif [ "$cmd" = "diff_k8s_secret" ] ; then
        _cmd_diff_k8s_secret "$@"
    else
        echo "$(basename "$0"): Error: Command '$cmd' invalid"
        _usage
    fi
fi
