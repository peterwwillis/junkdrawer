#!/usr/bin/env bash
# rscreen.sh - List screen and tmux sessions, pick one with dialog, and attach.

[ "${DEBUG:-0}" = "1" ] && set -x

_cleanup () { [ -n "${_TMP:-}" ] && rm -f "$_TMP" ; } ; trap _cleanup EXIT
_err () { printf "%s: Error: %s\n" "$0" "$*" 1>&2 ; }
_die () { _err "$*" ; exit 1 ; }

command -v dialog >/dev/null || _die "dialog is required but not installed"

_list_screen_sessions () {
    local sessions name status
    sessions="$(screen -ls 2>/dev/null)" || return 0
    while read -r name status ; do
        [ -n "${name:-}" ] || continue
        _targets+=("screen" "$name")
        _items+=("screen:$name" "$status")
    done < <(echo "$sessions" | sed -n 's/^\t\([0-9]\+\.[^\t]\+\)\t(\([^)]*\)).*/\1 \2/p')
}

_list_tmux_sessions () {
    local name
    command -v tmux >/dev/null || return 0
    while read -r name ; do
        [ -n "${name:-}" ] || continue
        _targets+=("tmux" "$name")
        _items+=("tmux:$name" "")
    done < <(tmux list-sessions -F '#{session_name}' 2>/dev/null)
}

_main () {

    local -a _items=()
    local -a _targets=()

    _list_screen_sessions
    _list_tmux_sessions

    if [ ${#_items[@]} -eq 0 ] ; then
        _die "No screen or tmux sessions found"
    fi

    _TMP=$(mktemp)
    dialog \
        --backtitle "rscreen" \
        --menu "Select a session to attach" 25 80 20 \
        "${_items[@]}" 2>"$_TMP"
    _rc=$?
    _selected="$(cat "$_TMP")"

    if [ "$_rc" -ne 0 ] || [ -z "${_selected:-}" ] ; then exit 0 ; fi

    _type="${_selected%%:*}"
    _name="${_selected#*:}"

    _attach_screen () {
        local id="$1"
        if screen -ls 2>/dev/null | grep -q "^[[:space:]]*${id}[[:space:]]*(Attached)" ; then
            exec screen -d -r "$id"
        else
            exec screen -r "$id"
        fi
    }

    case "$_type" in
        screen) _attach_screen "$_name" ;;
        tmux)   tmux attach -t "$_name" ;;
        *)      _die "Unknown session type: $_type" ;;
    esac

}

while true ; do
    _main
    sleep 0.25
done
