#!/usr/bin/env bash
# extract-script-comments.sh - Generate a TSV of any shebang-interpreted scripts and their commented descriptions

set -eu
[ "${DEBUG:-0}" = "1" ] && set -x

_process_script () {
    local script="$1"
    local -a description=()
    while read -r line ; do
        [ "${line:0:2}" = "#!" ] && continue
        [ "${line:0:1}" = "#" ] || break
        [ -n "$line" ] || break
        description+=("${line:2}")
    done <"$script"
    [ ${#description[@]} -gt 0 ] || return 0
    slug="${description[0]//\./}"
    slug=${slug//\.}
    slug=${slug,,[A-Z]}
    slug=${slug// /-}
    slug=${slug//[^a-zA-Z0-9-]}
    sanitized_desc="${description[0]//:/-}"
    desc_nameless="${sanitized_desc/#$script}"
    desc_name_only="${sanitized_desc// - *}"
    if [ "$desc_name_only" = "$sanitized_desc" ] || [ "$desc_nameless" = "$sanitized_desc" ] ; then
        desc_nameless=""
        desc_name_only="$sanitized_desc"
    fi
    content[$content_idx]="$script"
    content[$((content_idx+1))]="$slug"
    content[$((content_idx+2))]="$desc_name_only"
    content[$((content_idx+3))]="$desc_nameless"
    content[$((content_idx+4))]="${description[@]:1}"
    content_idx=$((content_idx+5))
}

_main () {
    local args=("$@")
    if [ ${#args[@]} -lt 1 ] ; then
        args=(".")
    fi
    for arg in "${args[@]}" ; do
        local myfiles=()
        if [ -d "$arg" ] ; then
            myfiles=($arg/*)
        else
            myfiles=("$arg")
        fi
        local shebang
        for file in "${myfiles[@]}" ; do
            [ -f "$file" ] || continue
            shebang="$(head -1 "$file")"
            if [ "${shebang:0:2}" = "#!" ] ; then
                _process_script "$file"
            fi
        done
    done

    printf "Script,Slug,Description_name,Description_nameless,Description_base64\n"
    idx=0
    while [ $idx -lt ${#content[@]} ] ; do
        printf "%s\t%s\t%s\t%s\t%s\n" \
            "${content[$idx]}" \
            "${content[$((idx+1))]}" \
            "${content[$((idx+2))]}" \
            "${content[$((idx+3))]}" \
            "$(printf "%s\n" "${content[$((idx+4))]}" | base64 -w0)"
        idx=$((idx+5))
    done

}

declare -a content=()
declare -i content_idx=0
_main "$@"
