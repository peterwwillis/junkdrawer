#!/usr/bin/env sh
# pi-dump-session-simple.sh - output text from a Pi (pi-coding-agent) session

set -eu
[ "${DEBUG:-0}" = "1" ] && set -x

PI_SESSIONS_DIR="${PI_SESSIONS_DIR:-$HOME/.pi/agent/sessions}"
# Truncate each tool result to this many characters (0 = no limit).
PI_DUMP_MAX_RESULT_CHARS="${PI_DUMP_MAX_RESULT_CHARS:-0}"

_usage () {
    cat <<EOUSAGE
Output the text of a Pi jsonl session.

Usage: $0 [DIR | SESSION_FILE.jsonl | SESSION_ID] ...

With no arguments, the most recently modified Pi session whose working directory is
the current directory is dumped. Pass a directory to use that directory instead, a
.jsonl file to dump that exact file, or a (partial) session UUID to look one up.

Pi sessions are stored in \$PI_SESSIONS_DIR (default: ~/.pi/agent/sessions), one
sub-directory per working directory. Pi session files are a tree (branches from
/fork or /tree); only the active branch (the one ending at the last entry) is output.

Environment:
  PI_SESSIONS_DIR              Where Pi stores sessions
  PI_DUMP_MAX_RESULT_CHARS     Truncate each tool result to N chars (default: 0 = no limit)
  DEBUG=1                      Trace the script

The output can be pasted into another AI agent to (roughly) resume the previous session.
EOUSAGE
    exit 1
}

_err () { printf "%s: Error: %s\n" "$0" "$*" 1>&2 ; }
_die () { _err "$*" ; exit 1 ; }

_newest () {
    # Print the most recently modified file among the arguments (ignoring non-existent ones).
    # shellcheck disable=SC2012
    ls -t "$@" 2>/dev/null | head -n 1
}

_find_session_file () {
    local arg="$1" abs encoded sdir found

    if [ -f "$arg" ] ; then
        printf '%s\n' "$arg"
        return 0
    fi

    if [ -d "$arg" ] ; then
        abs="$(cd "$arg" && pwd)"
        # Pi names the session dir after the cwd: /a/b.c/d -> --a-b.c-d--
        encoded="--$(printf '%s' "${abs#/}" | tr '/' '-')--"
        sdir="$PI_SESSIONS_DIR/$encoded"
        [ -d "$sdir" ] || _die "No Pi session directory for '$abs' (looked for '$sdir')"
        found="$(_newest "$sdir"/*.jsonl)"
        [ -n "$found" ] || _die "No Pi session files in '$sdir'"
        printf '%s\n' "$found"
        return 0
    fi

    # Otherwise treat it as a (partial) session UUID. Validate before using it in a glob.
    case "$arg" in
        *[!A-Za-z0-9-]* | '') _die "'$arg' is not a directory, a file, or a valid session ID" ;;
    esac
    found="$(_newest "$PI_SESSIONS_DIR"/*/*"$arg"*.jsonl)"
    [ -n "$found" ] || _die "No Pi session found matching '$arg' under '$PI_SESSIONS_DIR'"
    printf '%s\n' "$found"
}

_dump_jsonl () {
    local jsonfile="$1"
    jq -s -r --argjson max "$PI_DUMP_MAX_RESULT_CHARS" '
    def clip: if $max > 0 and length > $max
              then .[0:$max] + "\n...[truncated \(length - $max) chars]"
              else . end;
    # Flatten a content field (string, or array of blocks) to plain text.
    def txt: if type == "string" then .
             else ([.[]? | if .type == "text" then .text
                           elif .type == "image" then "[image omitted]"
                           else empty end] | join("\n"))
             end;

    . as $all
    | ($all | map(select(.id != null and .type != "session")) | INDEX(.id)) as $byid
    | ($all | map(select(.type != "session")) | last) as $leaf
    # Walk from the leaf up through parentId to get the active branch, oldest first.
    | [ $leaf | recurse(if .parentId != null then ($byid[.parentId] // empty) else empty end) ]
    | reverse
    | .[]
    | if .type == "message" then
        .message as $m
        | if $m.role == "user" then
            "--- USER ---\n\($m.content | txt)\n"
          elif $m.role == "assistant" then
            ( $m.content[]?
              | if .type == "text" then "--- ASSISTANT ---\n\(.text)\n"
                elif .type == "toolCall" then "--- ASSISTANT (TOOL CALL: \(.name)) ---\n\(.arguments | tojson)\n"
                else empty end ),
            ( if $m.stopReason == "error" or $m.stopReason == "aborted"
              then "--- SESSION ENDED (\($m.stopReason)) ---\n\($m.errorMessage // "no error message")\n"
              else empty end )
          elif $m.role == "toolResult" then
            "--- TOOL RESULT (\($m.toolName)\(if $m.isError then ", ERROR" else "" end)) ---\n\($m.content | txt | clip)\n"
          elif $m.role == "bashExecution" then
            "--- USER (BASH: \($m.command // "")) ---\n\(($m.output // "") | clip)\n"
          else empty end   # system prompt etc.
      elif .type == "compaction" or .type == "branch_summary" then
        "--- SYSTEM SUMMARY ---\n\(.summary // "")\n"
      else empty end' "$jsonfile"
}

_output_session_dump () {
    local arg="$1" jsonfile cwd name

    jsonfile="$(_find_session_file "$arg")"

    # First line of a Pi session file is the header: {"type":"session","cwd":...,"id":...}
    cwd="$(head -n 1 "$jsonfile" | jq -r '.cwd // "unknown"')"
    name="$(jq -r 'select(.type == "session_info") | .name' "$jsonfile" | tail -n 1)"

    echo "####################################################################################################"
    echo "##### NOTE: The following text is the rough back-and-forth from a past Pi session.             #####"
    echo "#####       You are receiving this in an attempt to continue the session where it left off.    #####"
    echo "#####                                                                                          #####"
    echo "#####       Consider the user's original intent, what the user was trying to accomplish,       #####"
    echo "#####       what was done, and whether it looks like there's anything left to be done.         #####"
    echo "#####       The previous session may have ended abnormally (e.g. a token/usage limit); if so   #####"
    echo "#####       the last section says why, and the final tool call may not have been acted on.     #####"
    echo "#####                                                                                          #####"
    echo "#####       Do research to determine any information you need to be able to continue the       #####"
    echo "#####       session. Provide the user a brief recap of where the session is now and what's     #####"
    echo "#####       left so they can see you understand what's going on. Ask the user questions to     #####"
    echo "#####       ensure you and the user are aligned on what should be done next.                   #####"
    echo "#####                                                                                          #####"
    echo "##### OUTPUTTING PI SESSION FROM FILE: $jsonfile"
    echo "##### SESSION NAME: ${name:-unnamed}   WORKING DIRECTORY: $cwd"
    echo "####################################################################################################"
    echo ""
    _dump_jsonl "$jsonfile"
}

_main () {
    local arg
    command -v jq >/dev/null 2>&1 || _die "jq is required"
    if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] ; then
        _usage
    elif [ $# -gt 0 ] ; then
        for arg in "$@" ; do
            _output_session_dump "$arg"
        done
    else
        _output_session_dump "$(pwd)"
    fi
}

_main "$@"
