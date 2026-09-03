#!/usr/bin/env bash
# ai-task-termic-attach.sh - attach already-running ai-task sessions to Termic
#
# Companion to ai-task.sh's `--termic new-task` post-launch hook, for
# sessions that were started without that flag. For each given worktree
# directory (or, with --all, every `aitask-*` tmux session currently
# running), auto-discovers the interactive claude session id registered
# at that path and runs:
#
#     termic new --from WORKTREE_DIR --resume SESSION_ID
#
# This makes Termic adopt the worktree as a new task and resume the SAME
# claude conversation - it does not touch or kill the existing tmux
# session, which keeps running independently. Kill it yourself once
# you've confirmed the new Termic task looks right.
#
# Requires: tmux, jq, claude, termic.
set -eu
[ "${DEBUG:-0}" = "1" ] && set -x

SCRIPT="$(basename "$0")"
_err()  { printf "%s: Error: %s\n" "$SCRIPT" "$*" 1>&2 ; }
_info() { printf "%s: Info: %s\n" "$SCRIPT" "$*" 1>&2 ; }
_die()  { _err "$@"; exit 1; }

_usage() {
    cat <<EOF
Usage: $SCRIPT [--all] [WORKTREE_DIR ...]

  --all          Discover every tmux session named aitask-* and resolve
                  each one's worktree dir from its pane's current path.
  WORKTREE_DIR    One or more explicit worktree directories to attach.

Exactly one of --all or one-or-more WORKTREE_DIR must be given.
EOF
    exit 1
}

command -v tmux >/dev/null 2>&1 || _die "tmux not found in PATH"
command -v jq >/dev/null 2>&1 || _die "jq not found in PATH"
command -v claude >/dev/null 2>&1 || _die "claude not found in PATH"
command -v termic >/dev/null 2>&1 || _die "termic not found in PATH"

worktree_dirs=()
all=0
while [ $# -gt 0 ] ; do
    case "$1" in
        --all)      all=1 ;;
        -h|--help)  _usage ;;
        -*)         _err "Unknown argument: $1"; _usage ;;
        *)          worktree_dirs+=("$1") ;;
    esac
    shift
done

if [ "$all" = "1" ] ; then
    [ "${#worktree_dirs[@]}" -eq 0 ] || _die "Don't combine --all with explicit worktree dirs."
    while IFS= read -r session ; do
        [ -n "$session" ] || continue
        path="$(tmux list-panes -t "$session" -F '#{pane_current_path}' 2>/dev/null | head -n1)"
        if [ -z "$path" ] ; then
            _err "Couldn't resolve pane path for session '$session' - skipping."
            continue
        fi
        worktree_dirs+=("$path")
    done < <(tmux list-sessions -F '#{session_name}' 2>/dev/null | grep '^aitask-' || true)
    [ "${#worktree_dirs[@]}" -gt 0 ] || _die "No aitask-* tmux sessions found."
fi

[ "${#worktree_dirs[@]}" -gt 0 ] || _usage

# _get_claude_session_id WORKTREE_DIR
#
# Same lookup ai-task.sh's --termic hook uses: the most recently started
# interactive claude session registered at WORKTREE_DIR, or empty if none.
_get_claude_session_id() {
    local worktree_dir="$1"
    claude agents --json --cwd "$worktree_dir" 2>/dev/null \
        | jq -r '[.[] | select(.kind == "interactive")]
                 | sort_by(.startedAt) | reverse
                 | .[0].sessionId // empty'
}

status=0
for worktree_dir in "${worktree_dirs[@]}" ; do
    if [ ! -d "$worktree_dir" ] ; then
        _err "Not a directory: $worktree_dir - skipping."
        status=1
        continue
    fi

    _info "Looking up claude session for $worktree_dir..."
    session_id="$(_get_claude_session_id "$worktree_dir")"
    if [ -z "$session_id" ] ; then
        _err "No interactive claude session found for $worktree_dir - skipping."
        status=1
        continue
    fi
    _info "  session id: $session_id"

    if ! termic_json="$(termic new --from "$worktree_dir" --resume "$session_id" --output-format json 2>&1)" ; then
        _err "termic new failed for $worktree_dir:"
        _err "$termic_json"
        status=1
        continue
    fi

    task_name="$(printf '%s' "$termic_json" | jq -r '.task.name // "<unknown>"')"
    task_path="$(printf '%s' "$termic_json" | jq -r '.task.path // "<unknown>"')"
    _info "Termic task created: $task_name (path $task_path)"
    _info "Open with: termic open $task_name"
done

exit "$status"
