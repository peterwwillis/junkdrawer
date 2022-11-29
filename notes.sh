#!/usr/bin/env sh
# notes.sh - shell script to manage hierarchy of note files
# Copyright (C) 2022  Peter Willis
set -eu

NOTES_VERSION="0.1.0"
NOTES_DIR="${NOTES_DIR:-$HOME/.notes.d}"
NOTES_DEFAULT_EXT=".md"

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
            __die "File not found: $_dir/$1"
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
    _bn="$(basename "$_note")"
    if [ -d "$_note" ] ; then
        printf "%s\n" "$_note/" | sed -E "s?^$NOTES_DIR/??g; s?//?/?g"
    else
        printf "%s\n" "$_note" | sed -E "s?^$NOTES_DIR/??g; s?//?/?g"
    fi
}

__notes_add () {
    _timestamp="$(date '+%s')"
    _newfile="note-$_timestamp$NOTES_DEFAULT_EXT"

    if [ $# -gt 1 ] ; then
        __die "Too many arguments (command allows only one)"
    elif [ $# -eq 1 ] ; then  
        _newfile="${1}$NOTES_DEFAULT_EXT"
    fi
    _newfile="$NOTES_DIR/$(__make_fancy_fn "$_newfile")"
    mkdir -p "$(dirname "$_newfile")"

    _tmpfile="$(mktemp "$NOTES_DIR/.notes.XXXXXX")"
    __default_editor "$_tmpfile"
    if [ ! -s "$_tmpfile" ] ; then
        __die "tmpfile was empty; not creating new note"
    fi

    mv -n "$_tmpfile" "$_newfile"
}

__make_fancy_fn () {
    _name="$1"
    _newfn="$(printf "%s\n" "$_name" | sed -e 's?\.d??g; s?/?\.d\/?g')"
    _newfn_dn="$(dirname "$_newfn")"
    printf "%s\n" "$_newfn"
}

__notes_edit () {
    if [ $# -lt 1 ] ; then
        __die "Not enough arguments: edit command requires at least one argument"
    fi
    for arg in "$@" ; do
        if [ -d "$NOTES_DIR/$arg" ] ; then
            __die "File is a directory: $NOTES_DIR/$arg"
        elif [ -e "$NOTES_DIR/$arg" ] ; then
            __default_editor "$NOTES_DIR/$arg"
        else
            __die "Could not find note '$arg'"
        fi
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
    _editors="${EDITOR:-mvim gvim vim vi emacs nano pico}"
    for editor in $_editors ; do
        if command -v "$editor" >/dev/null 2>&1 ; then
            case "$editor" in
                mvim|gvim)      $editor --nofork "$@" ; ;;
                *)              $editor "$@" ;;
            esac
            return $?
        fi
    done
}

__run_version () {
    printf "%s v%s\n" "$0" "$NOTES_VERSION"
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
Usage: $0 [OPTS] COMMAND [..]

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

__die () {
    [ $# -gt 0 ] && echo "$0: Error: $*"
    exit 1
}

__main () {
    [ -d "$NOTES_DIR" ] || mkdir -p "$NOTES_DIR"
    [ "$_set_verbose_mode" -eq 1 ] && set -x
    if [ "$_notes_add" -eq 1 ] ; then
        __notes_add "$@"
    elif [ "$_notes_edit" -eq 1 ] ; then
        __notes_edit "$@"
    elif [ "$_notes_delete" -eq 1 ] ; then
        __notes_delete "$@"
    elif [ "$_run_version" -eq 1 ] ; then
        __run_version "$@"
    elif [ "$_run_usage" -eq 1 ] ; then
        __usage
    elif [ "$_notes_list" -eq 1 ] || [ $# -lt 1 ] ; then
        __notes_list "$NOTES_DIR" "$@"
    fi
}

_notes_add=0 _notes_list=0 _notes_edit=0 _notes_delete=0 _run_usage=0
_run_version=0 _set_verbose_mode=0
while getopts "aledhVv" arg ; do
    case "$arg" in
        a)          _notes_add=1 ;;
        l)          _notes_list=1 ;;
        e)          _notes_edit=1 ;;
        d)          _notes_delete=1 ;;
        h)          _run_usage=1 ;;
        V)          _run_version=1 ;;
        v)          _set_verbose_mode=1 ;;
        *)          __die "Unknown argument '$arg'" ;;
    esac
done
shift $((OPTIND-1))

__main "$@"
