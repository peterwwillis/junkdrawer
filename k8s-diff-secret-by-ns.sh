#!/usr/bin/env bash
# k8s-diff-secret-by-ns.sh - Diff all of the secrets [and values] between two namespaces
# 
# This is a rather verbose/complete diffing of all the secrets between two namespaces.
# You're going to get a lot of noise (and it will take a long time) if there are
# a lot of Helm releases (or other secrets) in either namespace.
# 
# To just diff the names of the secrets, or just diff two individual secrets,
# see k8s-diff-secret.sh

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

_get_secret () {
    _ns="$1" _secret="$2" _file="$3"
    if ! kubectl -n "$_ns" get secret "$_secret" -o go-template='{{range $k,$v := .data}}{{printf "%s=%s" $k $v}}{{"\n"}}{{end}}'  2>/dev/null >"$_file" ; then
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

_cmd_compare_ns () {
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
  compare_ns NAMESPACE1 NAMESPACE2
  diff_k8s_secrets NS1 NS2 SECRET1 SECRET2 ..
  diff_k8s_secret NS1 NS1 SECRET

EOUSAGE
    exit 1
}


#################################################################

[ $# -gt 0 ] || _usage

cmd="$1"; shift
_cmd_"$cmd" "$@"
