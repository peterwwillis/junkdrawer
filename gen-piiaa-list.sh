#!/usr/bin/env bash
# gen-piiaa-list.sh - Generate list of scripts and descriptions for PIIAA
set -eu

extract-script-comments.sh "$@" | \
    while read -r LINE ; do
        IFS=$'\t' read -r -a myarr
        if [ ${#myarr[@]} -lt 4 ] ; then
            #echo "ERROR: array <4: ${myarr[@]}"
            myarr[2]="$(printf "%s\n" "${myarr[1]}" | base64 -d)"
        fi
        printf "%s\t%s\n" \
            "${myarr[0]#./}" \
            "${myarr[2]#* - }"
    done
