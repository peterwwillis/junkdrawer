#!/usr/bin/env sh
set -eu
[ "${DEBUG:-0}" = "1" ] && set -x

# Replace ${FOO} with the value of $FOO
_envsubst () {
    set +e ; while IFS= read -r foo ; do
        while : ; do
            match="$(expr "$foo" : '.*${\([a-zA-Z0-9_]*\)}')"
            [ -n "$match" ] || break
            eval new="\${$match:-}"
            # shellcheck disable=SC2154
            foo="$(printf "%s\n" "$foo" | sed -e "s?\${$match}?$new?g")"
            continue
        done
        printf "%s\n" "$foo"
    done ; set -e
}

_envsubst
