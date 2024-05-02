#!/usr/bin/env sh
# move-files-to-folders-by-ext.sh - Move all the files in a directory into folders named by extension
set -eu

_move_files () {
    for f in "$(readlink -f "$1")"/* ; do 
        [ -f "$f" ] || continue # ignore non-files
        EXT="$(printf "%s\n" "$f" | rev | cut -d . -f 1 | rev | tr A-Z a-z)" # get ext, make lowercase
        expr "$EXT" : ".*[^a-zA-z0-9]" >/dev/null && continue # ignore non-alphanumeric extensions
        [ -d "$EXT" ] || mkdir -p "$EXT"
        mv -v "$f" "$(dirname "$f")/$EXT/"
    done
}

# Usage:   move-files-to-folders-by-ext.sh [DIR]
_move_files "${1:-.}"
