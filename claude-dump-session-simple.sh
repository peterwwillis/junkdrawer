#!/usr/bin/env sh
# claude-dump-session-simple.sh - output text from a Claude Code session

set -eu
[ "${DEBUG:-0}" = "1" ] && set -x

_usage () {
    cat <<EOUSAGE
Output the text of Claude Code jsonl session data.

Usage: $0 [GIT_WORKTREE_DIR]

By default the script will look for Claude Code projects which have session jsonl files
with Git worktrees of the current directory. Pass a directory to the script to override
that directory.

If the jsonl file is found, this script will output a selection of the text from the
Claude Code session. This text can be pasted into another AI agent to (roughly) resume
the previous session.
EOUSAGE
    exit 1
}

_get_session_id () {
    local session_dir="$1"
    claude agents --json | jq -r --arg pwd "$session_dir" '[.[] | select(.cwd == $pwd)] | max_by(.startedAt) | .sessionId'
}

_err () { printf "%s: Error: %s\n" "$0" "$*" 1>&2 ; }
_die () { _err "$*" ; exit 1 ; }

_dump_jsonl () {
    local jsonfile="$1"
    jq -r '
    if ((.content | startswith("<local-command-caveat>")?) // false) or 
       ((.message.content | startswith("<local-command-caveat>")?) // false) then 
      empty
    elif .message?.role? then 
      (.message.role | ascii_upcase) as $r | 
      (.message.content | if type == "string" then [{type: "text", text: .}] else . end)[]? | 
      if .type == "text" then "--- \($r) ---\n\(.text)\n" 
      elif .type == "tool_use" then "--- \($r) (TOOL CALL: \(.name)) ---\n\(.input | tojson)\n" 
      elif .type == "tool_result" then "--- \($r) (TOOL RESULT) ---\n\(.content | if type=="string" then . else tojson end)\n" 
      else empty end 
    elif .type == "system" and .subtype == "away_summary" then 
      "--- SYSTEM SUMMARY ---\n\(.content)\n" 
    else 
      empty 
    end' "$jsonfile"

}

_output_session_dump () {
    local session_dir="$1" session_id
    session_id="$(_get_session_id "$session_dir")"

    if [ -z "$session_id" ] ; then
        _die "No claude session ID found for directory '$session_dir'"
    fi

    for jsonfile in ~/.claude/projects/*/"$session_id.jsonl" ; do

        if [ ! -e "$jsonfile" ] ; then
            _die "No claude project jsonl files found for current directory"
        else

            echo "####################################################################################################"
            echo "##### NOTE: The following text is the rough back-and-forth from a past Claude Code session.    #####"
            echo "#####       You are receiving this in an attempt to continue the session where it left off.    #####"
            echo "#####                                                                                          #####"
            echo "#####       Consider the user's original intent, what the user was trying to accomplish,       #####"
            echo "#####       what was done, and whether it looks like there's anything left to be done.         #####"
            echo "#####                                                                                          #####"
            echo "#####       Do research to determine any information you need to be able to continue the       #####"
            echo "#####       session. Provide the user a brief recap of where the session is now and what's     #####"
            echo "#####       left so they can see you understand what's going on. Ask the user questions to     #####"
            echo "#####       ensure you and the  user are aligned on what should be done next.                  #####"
            echo "#####                                                                                          #####"
            echo "##### OUTPUTTING CLAUDE CODE SESSION FROM FILE: $jsonfile #####"
            echo "####################################################################################################"
            echo ""
            _dump_jsonl "$jsonfile"
        fi

    done
}

_main () {
    local dir
    if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] ; then
        _usage
    elif [ $# -gt 0 ] ; then
        for dir in "$@" ; do
            _output_session_dump "$dir"
        done
    else
        _output_session_dump "$(pwd)"
    fi
}

_main "$@"
