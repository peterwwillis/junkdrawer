#!/usr/bin/env bash
# helm-list-fast.sh - a much faster version of 'helm list -A'
#
# About:
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
#  - add columns 'STATUS', 'CHART', 'APP VERSION'
#  - support single-namespace operation

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
    c=0 release_c=0
    declare -a headers
    declare -A releases=() lastreleasever=()

    while read -r -a secret ; do

        # namespace name type data age
        #echo "secret ${secret[@]}"
        if [ $c -eq 0 ] ; then
            headers=( "${secret[@]}" )
            c=$((c+1))
            continue
        fi

        release="${secret[1]%.v*}"
        releasever="${secret[1]##*.v}"
        nsrelease="${secret[0]}/$release"
        #echo "Namespace ${secret[0]} Release ${release}"

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

    done < <(kubectl get secrets \
        --selector=owner=helm \
        --field-selector type="helm.sh/release.v1" \
        --output=wide \
        --all-namespaces)

    declare -a getlast=()

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


if [ $# -gt 0 ] && [ "$1" = "getlast" ] ; then
    shift
    _cmd_getlast "$@"
else
    _main | column -t
fi
