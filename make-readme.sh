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
    for i in "${scripts[@]}" ; do
        printf "%s\n" " * [$i](#$i)"
    done
    printf "%s\n\n\n" "---"

    printf "%s\n" "${content[@]}"
}

declare -a content=()
declare -a scripts=()
_main "$@"
