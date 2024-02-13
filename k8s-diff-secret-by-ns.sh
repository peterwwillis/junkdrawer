#!/usr/bin/env sh
set -u
[ "${DEBUG:-0}" = "1" ] && set -x

SCRIPT="$(basename "${BASH_SOURCE[0]}")"

PARALLEL_LIMIT="${PARALLEL_LIMIT:-20}"


_cleanup () {
    ret=$?
    rm -f "${tmp1:-}" "${tmp2:-}"
    exit $ret
}
trap _cleanup EXIT TERM INT HUP ABRT STOP QUIT

_get_secret () {
    _ns="$1" _secret="$2" _file="$3"
    if ! kubectl -n "$_ns" get secret "$_secret" -o yaml 2>/dev/null >"$_file" ; then
        echo "# not found: namespace $_ns secret $_secret"
        return 1
    else
        yq -M .data <"$_file" >"$_file.data"
        mv -f "$_file.data" "$_file"
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
    ns1="$1" ns2="$2" secret="$3"
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
    NS1="$1" NS2="$2" ; shift 2
    secrets1="$(kubectl -n "$NS1" get secret --no-headers=true | awk '{print $1}')"
    secrets2="$(kubectl -n "$NS2" get secret --no-headers=true | awk '{print $1}')"

    _cmd_diff_k8s_secrets "$NS1" "$NS2" $secrets1

    donesecrets=""
    for SECRET in $secrets1 ; do
        donesecrets="$donesecrets $SECRET"
    done

    todosecrets2=""
    for SECRET in $secrets2 ; do

        missing=1
        for donesecret in $donesecrets ; do
            if [ "$donesecret" = "$SECRET" ] ; then
                missing=0
                break
            fi
        done

        if [ $missing -eq 1 ] ; then
            todosecrets2="$todosecrets2 $SECRET"
        fi
    done

    if [ -n "$todosecrets2" ] ; then
        _cmd_diff_k8s_secrets "$NS1" "$NS2" $todosecrets2
    fi
}

_usage () {
    cat <<EOUSAGE
Usage: $SCRIPT COMMAND [..]

Diff k8s secrets between two namespaces

Commands:
  compare_ns NAMESPACE1 NAMESPACE2

EOUSAGE
    exit 1
}


#################################################################

[ $# -gt 0 ] || _usage

cmd="$1"; shift
_cmd_"$cmd" "$@"
