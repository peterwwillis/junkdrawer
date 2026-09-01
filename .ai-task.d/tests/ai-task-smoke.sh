#!/usr/bin/env bash
# ai-task-smoke.sh - end-to-end smoke test for ai-task.sh `start`
#
# Creates a throwaway Linear ticket, runs a REAL `ai-task.sh start` against
# it with a do-nothing prompt (no tools, no work) on the Haiku model, and
# verifies the launched tmux session comes up with a live claude process.
# A "READY" reply from claude is the strong signal; a live pane process with
# no fatal error is the minimum pass. Cost: one short Haiku turn per run
# (a fraction of a cent).
#
# Runs:
#   --basic   your config live EXCEPT AWS ReadOnly mode (--no-aws-readonly-role)
#   --aws     AWS ReadOnly mode exercised (config's AITASK_AWS_ROLE_READONLY);
#             needs a valid `aws-sso login` session
#   --clean   clean up after an interrupted run (uses tests/.last-run.env)
#   (no args) both --basic and --aws
#
# Cleanup after every run: tmux session killed, worktrees removed, ticket
# canceled. The run's coordinates are recorded in .last-run.env as it goes,
# so `make clean` (or --clean) can recover from a hard kill.
#
# Requires: linear (authed), claude, tmux, jq, git. --aws additionally
# requires aws-sso + aws with a valid session.
#
# NOTE: your ~/.ai-taskrc config stays live for these runs on purpose
# (AITASK_TERMIC=new-task will fire; AITASK_MODEL is overridden by --model).
set -eu

SCRIPT_NAME="$(basename "$0")"
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/../.." && pwd)"
AITASK="$REPO_ROOT/ai-task.sh"
STATE_FILE="$TESTS_DIR/.last-run.env"

MODEL="haiku"
PANE_WAIT=150   # max seconds to wait for claude's READY reply
PANE_POLL=5

SANDBOX="" TICKET="" SESSION="" WORKTREES=""
LOGDIR=""
results_pass=0 results_fail=0

_err()  { printf "%s: Error: %s\n" "$SCRIPT_NAME" "$*" 1>&2; }
_info() { printf "%s: Info: %s\n" "$SCRIPT_NAME" "$*" 1>&2; }
_die()  { _err "$@"; exit 1; }

check () {  # check DESC STATUS
    if [ "$2" = "0" ]; then
        printf 'PASS: %s\n' "$1"
        results_pass=$((results_pass + 1))
    else
        printf 'FAIL: %s\n' "$1"
        results_fail=$((results_fail + 1))
    fi
}

# ── state recording (for --clean recovery) ───────────────────────────────────

record_state () {
    {
        printf 'SANDBOX=%q\n'   "${SANDBOX:-}"
        printf 'TICKET=%q\n'    "${TICKET:-}"
        printf 'SESSION=%q\n'   "${SESSION:-}"
        printf 'WORKTREES=%q\n' "${WORKTREES:-}"
    } > "$STATE_FILE"
}

# ── cleanup ──────────────────────────────────────────────────────────────────

cleanup_run () {
    if [ -n "$SESSION" ] ; then
        tmux kill-session -t "$SESSION" 2>/dev/null || true
    fi
    local wt
    for wt in ${WORKTREES:-} ; do
        git -C "$REPO_ROOT" worktree remove --force "$wt" 2>/dev/null || rm -rf "$wt"
    done
    git -C "$REPO_ROOT" worktree prune 2>/dev/null || true
    if [ -n "$TICKET" ] ; then
        linear issue update "$TICKET" --state Canceled >/dev/null 2>&1 \
            || _info "Couldn't cancel throwaway ticket $TICKET - cancel it manually."
    fi
}

finish () {
    cleanup_run
    if [ "${KEEP:-0}" = "1" ] ; then
        _info "KEEP=1 - sandbox left at $SANDBOX (logs, pane transcripts, worktrees)"
    else
        rm -rf "$SANDBOX"
    fi
}

# ── helpers ──────────────────────────────────────────────────────────────────

pane_capture () { tmux capture-pane -p -t "$1" 2>/dev/null || true; }

wait_for_pane_text () {  # SESSION PATTERN
    local elapsed=0
    while [ "$elapsed" -lt "$PANE_WAIT" ] ; do
        if pane_capture "$1" | grep -q -- "$2" ; then return 0 ; fi
        sleep "$PANE_POLL"
        elapsed=$((elapsed + PANE_POLL))
    done
    return 1
}

create_ticket () {
    local out id
    out="$(linear issue create --team DVOPS \
        -t "ai-task smoke test (throwaway - safe to delete) $(date +%H%M%S)" \
        -d "Created by .ai-task.d/tests/ai-task-smoke.sh to exercise ai-task.sh start end to end. Safe to delete." 2>&1)"
    id="$(printf '%s\n' "$out" | grep -Eo '[A-Z]+-[0-9]+' | head -n1)"
    [ -n "$id" ] || _die "Couldn't parse created ticket id from linear output: $out"
    printf '%s' "$id"
}

# ── --clean mode ─────────────────────────────────────────────────────────────

if [ "${1:-}" = "--clean" ] ; then
    [ -e "$STATE_FILE" ] || _die "No $STATE_FILE - nothing to clean."
    # shellcheck source=/dev/null
    . "$STATE_FILE"
    cleanup_run
    rm -f "$STATE_FILE"
    _info "Cleaned: session '${SESSION:-<none>}', worktrees '${WORKTREES:-<none>}', ticket '${TICKET:-<none>}', sandbox '${SANDBOX:-<none>}'."
    exit 0
fi

# ── setup ────────────────────────────────────────────────────────────────────

MODE="${1:---all}"
case "$MODE" in
    --basic|--aws) ;;
    --all) MODE="--basic --aws" ;;
    *) _die "Usage: $SCRIPT_NAME [--basic|--aws|--clean] (no args = both runs)" ;;
esac

for tool in linear claude tmux jq git ; do
    command -v "$tool" >/dev/null 2>&1 || _die "Missing required command '$tool' in PATH"
done
linear auth whoami >/dev/null 2>&1 || _die "linear CLI is not authenticated (run: linear auth login)"
[ -x "$AITASK" ] || _die "ai-task.sh not found/executable at $AITASK"

SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/aitask-smoke.XXXXXX")"
LOGDIR="$SANDBOX/logs"
PROMPT_FILE="$SANDBOX/smoke-prompt.txt"
mkdir -p "$LOGDIR"
record_state
trap finish EXIT

# The do-nothing prompt: claude must start, but must not do any work.
cat > "$PROMPT_FILE" <<'EOP'
This is an automated smoke test of the ai-task launch pipeline - its only
purpose is verifying the session starts. Do NOT do any work: do not use
tools, do not read or write files, do not run any commands. Reply with the
single word READY and nothing else, then stop.
EOP

_info "Throwaway ticket + sandbox ready. Sandbox: $SANDBOX"
# ── one start run + verification ─────────────────────────────────────────────

# run_start LABEL WTDIR [extra start args...]
run_start () {
    local label="$1" wt_root="$2"; shift 2
    local err="$LOGDIR/start-$label.err" out="$LOGDIR/start-$label.out" st=0

    _info "[$label] ai-task.sh start $TICKET $* (model=$MODEL)"
    "$AITASK" start "$TICKET" --model "$MODEL" \
        --prompt-file "$PROMPT_FILE" --worktree-root "$wt_root" "$@" \
        > "$out" 2> "$err" || st=$?
    check "[$label] ai-task.sh start exits 0" "$st"
    if [ "$st" != "0" ] ; then
        sed 's/^/    | /' "$err" | tail -n 20 1>&2
        return 1
    fi

    SESSION="$(sed -n 's/^.*Session:[[:space:]]*//p' "$err" | head -n1)"
    WORKTREES="$WORKTREES $(sed -n 's/^.*Worktree:[[:space:]]*//p' "$err" | head -n1)"
    record_state
    [ -n "$SESSION" ] || { check "[$label] session name parsed from start output" 1; return 1; }

    verify_session "$label" "$SESSION"
}

# verify_session LABEL SESSION
verify_session () {
    local label="$1" session="$2"
    local st=0 pane_pid="" transcript="$LOGDIR/pane-$label.txt"

    st=0; tmux has-session -t "$session" 2>/dev/null || st=$?
    check "[$label] tmux session '$session' exists" "$st"

    pane_pid="$(tmux list-panes -t "$session" -F '#{pane_pid}' 2>/dev/null | head -n1)"
    st=0; [ -n "$pane_pid" ] && kill -0 "$pane_pid" 2>/dev/null || st=$?
    check "[$label] pane process alive (pid ${pane_pid:-?})" "$st"

    if wait_for_pane_text "$session" "READY" ; then
        check "[$label] claude answered READY (and did no work)" 0
    else
        check "[$label] claude answered READY within ${PANE_WAIT}s" 1
        # Minimum pass: process still alive means claude started; the reply
        # may just be slow (model latency, termic poll, TUI rendering).
        st=0; kill -0 "$pane_pid" 2>/dev/null || st=$?
        check "[$label] claude still alive without replying (started but slow)" "$st"
    fi

    pane_capture "$session" > "$transcript"
    # Informational error scan - TUI text can false-positive these, so this
    # never fails the run by itself; the process-alive checks above do that.
    if grep -Ein 'API Error|Invalid model|not found|refused|FATAL|ENOENT|Traceback' "$transcript" | head -n 5 | sed 's/^/    | pane: /' 1>&2 ; then
        _info "[$label] (info) pane mentions error-like text above - see transcript"
    fi

    # Show the operator that claude really came up.
    _info "[$label] pane tail:"
    tail -n 12 "$transcript" | sed 's/^/    | /' 1>&2
}

check_generated_files () {  # LABEL WTDIR [AWS_ENABLED]
    local label="$1" wt="$2" aws_enabled="${3:-0}" f

    for f in "$wt/.aitask-prompt.txt" "$wt/.aitask-launch.sh" ; do
        if [ -s "$f" ] ; then
            check "[$label] generated $(basename "$f")" 0
        else
            check "[$label] generated $(basename "$f")" 1
        fi
    done
    if [ "$aws_enabled" = "1" ] ; then
        for f in config credentials README.md ; do
            if [ -s "$wt/.aitask-aws/$f" ] ; then
                check "[$label] .aitask-aws/$f minted" 0
            else
                check "[$label] .aitask-aws/$f minted" 1
            fi
        done
        if grep -q "AWS ReadOnly mode is on" "$wt/.aitask-prompt.txt" ; then
            check "[$label] prompt contains AWS ReadOnly appendix" 0
        else
            check "[$label] prompt contains AWS ReadOnly appendix" 1
        fi
    fi
    _info "[$label] .claude/settings.local.json:"
    sed 's/^/    | /' "$wt/.claude/settings.local.json" 1>&2
}

check_linear_state () {  # LABEL
    local st=0 state
    state="$(linear issue view "$TICKET" --json 2>/dev/null | jq -r '.state.name // ""')"
    [ "$state" = "In Progress" ] || st=1
    check "[$1] Linear state set to 'In Progress' (got: ${state:-<none>})" "$st"
}

report_termic () {  # LABEL START_ERRFILE
    if grep -q "Termic" "$2" ; then
        _info "[$1] Termic hook (config AITASK_TERMIC=new-task):"
        grep "Termic" "$2" | sed 's/^/    | /' 1>&2
    fi
}

# ── runs ─────────────────────────────────────────────────────────────────────

TICKET="$(create_ticket)"
_info "Created throwaway ticket: $TICKET"
record_state

if [ "${MODE#--basic}" != "$MODE" ] ; then
    _info "── Run A: basic startup (AWS ReadOnly skipped) ─────────────────"
    run_start basic "$SANDBOX/wt-basic" --no-aws-readonly-role \
        && check_generated_files basic "$SANDBOX/wt-basic/$(printf '%s' "$TICKET" | tr '[:upper:]' '[:lower:]')" 0 \
        && check_linear_state basic
    report_termic basic "$LOGDIR/start-basic.err"
fi

if [ "${MODE#--aws}" != "$MODE" ] ; then
    _info "── Run B: AWS ReadOnly mode (config as-is) ─────────────────────"
    run_start aws "$SANDBOX/wt-aws" --reuse-worktree \
        && check_generated_files aws "$SANDBOX/wt-aws/$(printf '%s' "$TICKET" | tr '[:upper:]' '[:lower:]')" 1
    report_termic aws "$LOGDIR/start-aws.err"
fi

# ── summary ──────────────────────────────────────────────────────────────────

printf '\n%d passed, %d failed\n' "$results_pass" "$results_fail"
[ "$results_fail" -eq 0 ]

