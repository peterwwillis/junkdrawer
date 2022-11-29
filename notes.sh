#!/usr/bin/env sh
# notes.sh - shell script to manage hierarchy of note files
# Copyright (C) 2022  Peter Willis
set -eu

NOTES_VERSION="0.1.0"
NOTES_DIR="${NOTES_DIR:-$HOME/.notes.d}"
NOTES_DEFAULT_EXT=".md"
NOTES_APP_NAME="${NOTES_APP_NAME:-$(basename "$0")}"

__notes_list () {
    _dir="$1"; shift 1
    if [ $# -gt 0 ] ; then
        if [ -e "$_dir/$1" ] && [ ! -d "$_dir/$1" ] ; then
            __note_list "$_dir/$1"
        elif [ -d "$_dir/$1" ] ; then
            _newdir="$1"; shift
            __notes_list "$_dir/$_newdir" "$@"
            return $?
        elif [ ! -e "$_dir/$1" ] ; then
            __err "File not found: $_dir/$1"
            return 1
        fi
    elif [ -d "$_dir" ] ; then
        for note in "$_dir"/* ; do
            _bn="$(basename "$note")"
            [ "$_bn" = '*' ] && continue # skip when no files matched the glob
            __note_list "$note"
        done
    elif [ -e "$_dir/$1" ] ; then
        __note_list "$_dir/$1"
    fi
}
__note_list () {
    _note="$1"; shift
    [ -d "$_note" ] && _note="$_note/"
    printf "%s\n" "$_note" | sed -E "s?^$NOTES_DIR/??g; s?//?/?g"
}

__notes_add () {
    _timestamp="$(date '+%s')"
    _newfile="note-$_timestamp$NOTES_DEFAULT_EXT"

    if [ $# -gt 1 ] ; then
        __die "Too many arguments (command allows only one)"
    elif [ $# -eq 1 ] ; then  
        _newfile="${1}"
    fi
    _newfile="$NOTES_DIR/$_newfile"
    mkdir -p "$(dirname "$_newfile")"
    touch "$_newfile"
}

__notes_edit () {
    [ $# -lt 1 ] && __die "Command requires at least one argument"
    for arg in "$@" ; do
        if [ -d "$NOTES_DIR/$arg" ] ; then
            __die "File is a directory: $NOTES_DIR/$arg"
        fi
        if ! __notes_list "$NOTES_DIR" "$arg" ; then
            __notes_add "$arg"
        fi
        __default_editor "$NOTES_DIR/$arg"
    done
}

__notes_delete () {
    [ $# -lt 1 ] && __die "Command requires arguments"
    for arg in "$@" ; do
        _fn="$NOTES_DIR/$arg"
        if [ ! -e "$_fn" ] ; then
            __die "File not found: $_fn"
        elif [ -d "$_fn" ] ; then
            __die "File is a directory, cannot delete: $_fn"
        else
            rm "$_fn"
        fi
    done
}

__default_editor () {
    _editors="${EDITOR:-open mvim gvim vim vi emacs nano pico}"
    for editor in $_editors ; do
        if command -v "$editor" >/dev/null 2>&1 ; then
            case "$editor" in
                open)           open "$@" ;;
                mvim|gvim)      $editor --nofork "$@" ;;
                *)              $editor "$@" ;;
            esac
            return $?
        fi
    done
}

__run_version () {
    printf "%s v%s\n" "$NOTES_APP_NAME" "$NOTES_VERSION"
}

__cleanup () {
    oldres=$?
    if [ -n "${_tmpfile:-}" ] ; then
        rm -f "$_tmpfile"
    fi
    return $oldres
}
trap __cleanup EXIT

__usage () {
    cat <<EOUSAGE
Usage: $NOTES_APP_NAME [OPTS] COMMAND [..]

Options:
  -a [NOTE]             Add a NOTE
  -l [NOTE]             List a NOTE
  -e NOTE [..]          Edit a NOTE
  -d NOTE [..]          Delete a NOTE
  -h                    This screen
  -v                    Verbose mode
  -V                    Display version
EOUSAGE
    __die
}

__err () { echo "$NOTES_APP_NAME: Error: $*" ; }
__die () {
    [ $# -gt 0 ] && __err "$@"
    exit 1
}

__main () {
    [ -d "$NOTES_DIR" ] || mkdir -p "$NOTES_DIR"
    [ "$_set_verbose_mode" -gt 0 ] && set -x
    if [ "$_notes_add" -gt 0 ] ; then
        __notes_add "$@"
    elif [ "$_notes_edit" -gt 0 ] ; then
        __notes_edit "$@"
    elif [ "$_notes_list" -gt 0 ] ; then
        __notes_list "$NOTES_DIR" "$@"
    elif [ "$_run_version" -gt 0 ] ; then
        __run_version "$@"
    elif [ "$_notes_delete" -gt 0 ] ; then
        __notes_delete "$@"
    else
        __usage
    fi
}

_notes_add=0 _notes_list=0 _notes_edit=0 _notes_delete=0 _run_usage=0
_run_version=0 _set_verbose_mode=0
while getopts "aledhVv" arg ; do
    case "$arg" in
        a)          _notes_add=$((_notes_add+1)) ;;
        l)          _notes_list=$((_notes_list+1)) ;;
        e)          _notes_edit=$((_notes_edit+1)) ;;
        d)          _notes_delete=$((_notes_delete+1)) ;;
        h)          _run_usage=1 ;;
        V)          _run_version=1 ;;
        v)          _set_verbose_mode=1 ;;
        *)          __die "Unknown argument '$arg'" ;;
    esac
done
shift $((OPTIND-1))

__main "$@"
