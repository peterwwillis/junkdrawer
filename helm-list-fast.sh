#!/usr/bin/env bash
# helm-list-fast.sh - Much faster version of 'helm list'
#
#   This script exists because 'helm list' will query the Kubernetes API server
#   in such a way that secrets take a looooong time to come back.
#   To avoid that wait, here I just grab the secrets list with kubectl, and then
#   parallelize grabbing individual last release files to determine their last
#   updated date.
#   This is about 6x faster than 'helm list' (on my cluster).
# 
# Requires:
#   - kubectl, base64, gzip, jq, xargs, column
# 
# TODO:
#  - [ ] add columns 'STATUS', 'CHART', 'APP VERSION'
#  - [x] support single-namespace operation

set -eu
[ "${DEBUG:-0}" = "1" ] && set -x


_getlastparallel () {
    for i in "${getlast[@]}" ; do
        echo "$i"
    done | xargs -I{} -P10 sh -c "${BASH_SOURCE[0]} getlast {}"
}

_cmd_getlast () {
    arg="$1"; shift
    IFS=/ read -r name ns lastver <<<"$arg"
    kubectl -n "$ns" get secret "$lastver" -o json \
        | jq -r '.data.release' \
        | base64 -d \
        | base64 -d \
        | gzip -cd \
        | jq -r "\"$name\t$ns\t$lastver\t\" + .info.last_deployed"
}

_main () {
    local c=0 current_ns
    local -a get_release_args headers=() getlast=()
    local -A releases=() lastreleasever=()

    get_release_args=(kubectl get secrets --selector=owner=helm \
        --field-selector type="helm.sh/release.v1" --output=wide)

    if [ $_all_namespaces -eq 1 ] ; then
        get_release_args+=(--all-namespaces)
        unset _namespace
    else
        current_ns="$(kubectl config view --minify --output 'jsonpath={..namespace}')"
        if [ -z "${_namespace:-}" ] ; then
            _namespace="$current_ns"
        fi
        get_release_args+=(-n "$_namespace")
    fi

    while read -r -a secret_desc ; do

        local _ns='' _name='' _type='' _data='' _age=''
        if [ -n "${_namespace:-}" ] ; then
            _ns="$_namespace"
            headers+=("NAMESPACE")
            _name="${secret_desc[0]}"
            _type="${secret_desc[1]}"
            _data="${secret_desc[2]}"
            _age="${secret_desc[3]}"
        else
            _ns="${secret_desc[0]}"
            _name="${secret_desc[1]}"
            _type="${secret_desc[2]}"
            _data="${secret_desc[3]}"
            _age="${secret_desc[4]}"
        fi

        if [ $c -eq 0 ] ; then
            headers+=( "${secret_desc[@]}" )
            c=$((c+1))
            continue
        fi

        release="${_name%.v*}"
        releasever="${_name##*.v}"
        nsrelease="$_ns/$release"

        if [ -n "${releases[$nsrelease]+1}" ] ; then
            #echo "Release exists"
            releases[$nsrelease]=$((${releases[$nsrelease]}+1))
            if [ $releasever -gt ${lastreleasever[$nsrelease]} ] ; then
                lastreleasever[$nsrelease]="$releasever"
            fi
        else
            #echo "Release does not exist"
            releases[$nsrelease]=1
            lastreleasever[$nsrelease]="$releasever"
        fi

        c=$((c+1))

    done < <( "${get_release_args[@]}" )

    # turn "NS/sh.helm.release.v1.NAME" into "sh.helm.release.v1.NAME/NS/sh.helm.release.v1.NAME.vVERSION"
    for k in "${!releases[@]}" ; do
        ns="${k%%/*}"
        name="${k##*/}"
        lastver="$name.v${lastreleasever[$k]}"
        getlast+=("$name/$ns/$lastver")
    done

    printf "%s\t%s\t%s\t%s\n" "NAME" "NAMESPACE" "REVISION" "UPDATED"
    (
        while IFS=$'\t' read -r -a line ; do
            printf "%s\t%s\t%s\t%s\n" \
                "${line[0]##sh.helm.release.v1.}" \
                "${line[1]}" \
                "${line[2]##sh.helm.release.[^.]*.v}" \
                "${line[3]}"
        done < <(_getlastparallel)
    ) | sort -k1
}

_usage () {
    cat <<EOUSAGE
Usage: $(basename "$0") [OPTIONS] [COMMAND]

Retrieve Helm releases much faster than the stock 'helm list' command.

The Kubernetes API server returns secrets much faster for specific types
of queries. The 'kubectl' command will make these queries if you use
the '-o wide' output format, but 'helm' will not make that kind of query.

Therefore, this script uses the 'kubectl -o wide' output to reconstruct
Helm's list output. On my cluster this results in a 6x speed-up.

Commands:
  getlast NAME/NS/LASTVER

Options:
  -n NAME       Get Helm releases from namespace NAME
  -A            Get Helm releases from all namespaces
  -h            This help menu
EOUSAGE
    exit 1
}

_run_usage=0 _all_namespaces=0 _namespace=''
while getopts "hHvAn:" arg ; do
    case "$arg" in
        h)          _run_usage=1 ;;
        A)          _all_namespaces=1 ;;
        n)          _namespace="$OPTARG" ;;
        *)          _die "Unknown argument '$arg'" ;;
    esac
done
shift $((OPTIND-1))

if [ $_run_usage -eq 1 ] ; then
    _usage
elif [ $# -gt 0 ] && [ "$1" = "getlast" ] ; then
    shift
    _cmd_getlast "$@"
else
    _main | column -t
fi
