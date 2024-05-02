#!/usr/bin/env bash
# make-readme.sh - Generates a README.md based on the comment descriptions after a shebang in a script

set -eu
[ "${DEBUG:-0}" = "1" ] && set -x

_info () { printf "%s\n" "$0: Info: $*" 1>&2 ; }

_do_script () {
    local script="$1"
    local -a description=()
    while read -r line ; do
        [ "${line:0:2}" = "#!" ] && continue
        [ "${line:0:1}" = "#" ] || break
        [ -n "$line" ] || break
        description+=("${line:2}")
    done <"$script"
    [ ${#description[@]} -gt 0 ] || return 0
    scripts+=("$script")
    slug="${description[0]//\./}"
    slug=${slug//\.}
    slug=${slug,,[A-Z]}
    slug=${slug// /-}
    slug=${slug//[^a-zA-Z0-9-]}
    sanitized_desc="${description[0]//:/-}"
    tableofcontents+=("$slug" "$sanitized_desc")
    content+=( "$(printf "%s\n" "## [${description[0]}](./$script)" "<blockquote>" "${description[@]:1}" "</blockquote>" )" $'\n' )
}

_main () {
    local dir="${1:-.}"
    cd "$dir"
    local line
    for i in * ; do
        [ -f "$i" ] || continue
        line="$(head -1 "$i")"
        if [ "${line:0:2}" = "#!" ] ; then
            _do_script "$i"
        fi
    done

    printf "%s\n" "Table of Contents"

    while read -r slug ; do
        printf "%s\n" " * [${tableofcontents[$slug]}](#$slug)"
    done <<<"$(printf "%s\n" "${!tableofcontents[@]}" | sort)"

    printf "%s\n\n\n" "---"

    printf "%s\n" "${content[@]}"
}

declare -a content=()
declare -A tableofcontents=()
_main "$@"
