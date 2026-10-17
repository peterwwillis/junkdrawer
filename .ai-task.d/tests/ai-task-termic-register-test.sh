#!/usr/bin/env bash
# ai-task-termic-register-test.sh - OFFLINE test of how ai-task.sh launches a
# headless claude run and registers it with Termic (--termic new-task).
#
# Unlike ai-task-smoke.sh this touches no Linear, tmux, Termic or API: it
# extracts the relevant functions from ai-task.sh, generates the real
# headless launcher into a temp dir, and runs it against stub `claude` /
# `termic` binaries.
#
# What it pins down (the regressions it guards):
#  - a headless `claude -p` session is only resumable once its transcript
#    holds a user message, and Termic's `--resume` applies on a task's first
#    spawn only -> registration must wait for that message, not fire at launch
#  - claude hides sdk-cli sessions from its /resume picker -> the launcher must
#    set CLAUDE_CODE_ENTRYPOINT to a non-sdk value, inline (it runs under
#    `env -i`)
#  - the session id is pre-assigned (--session-id) and the launcher never
#    passes --session-id for an id that already exists
#
# Usage: bash ai-task-termic-register-test.sh   (AITASK_SH=path to test another copy)
# shellcheck disable=SC2034  # many vars below are consumed by the sourced functions
set -eu

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AITASK="${AITASK_SH:-$HERE/../../ai-task.sh}"
[ -f "$AITASK" ] || { echo "ai-task.sh not found at $AITASK" >&2; exit 2; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/aitask-termic-test.XXXXXX")"
trap 'rm -rf "${WORK:?}"' EXIT

pass=0 fail=0
ok ()   { pass=$((pass + 1)); printf '  ok   - %s\n' "$*"; }
bad ()  { fail=$((fail + 1)); printf '  FAIL - %s\n' "$*"; }
check () {  # DESC CMD...
    local desc="$1"; shift
    if "$@" ; then ok "$desc" ; else bad "$desc" ; fi
}

UUID_RE='[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'

# ── functions under test, extracted verbatim ────────────────────────────────
extract () {  # FUNCTION_NAME (prints nothing if the function does not exist)
    awk -v fn="$1" '$0 ~ "^" fn " \\(\\) \\{" {f=1} f {print} f && /^}/ {exit}' "$AITASK"
}
LOG="$WORK/msgs.log"
FUNCS="$WORK/funcs.sh"
{
    printf '_info () { printf "INFO: %%s\\n" "$*" >> "%s"; }\n' "$LOG"
    printf '_err () { printf "ERR: %%s\\n" "$*" >> "%s"; }\n' "$LOG"
    printf '_warn () { printf "WARN: %%s\\n" "$*" >> "%s"; }\n' "$LOG"
    for fn in _write_launcher _register_termic _do_termic_new_task _new_uuid \
              _transcript_has_user_line _wait_for_transcript ; do
        extract "$fn"
    done
} > "$FUNCS"
# Only functions that exist in every version are mandatory, so this test can
# also be pointed at an older ai-task.sh and FAIL on behavior, not on setup.
[ "$(grep -c '^_write_launcher\|^_do_termic_new_task' "$FUNCS")" = 2 ] \
    || { echo "could not extract functions from $AITASK" >&2; exit 2; }

# ── stubs ───────────────────────────────────────────────────────────────────
BIN="$WORK/bin"; mkdir -p "$BIN"
# claude: records its argv and CLAUDE_CODE_ENTRYPOINT, prints a result event
# carrying the session id it was given (--session-id / --resume).
cat > "$BIN/claude" <<'EOS'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$STUB_CLAUDE_ARGS"
printf '%s' "${CLAUDE_CODE_ENTRYPOINT:-}" > "$STUB_CLAUDE_ENTRY"
sid="11111111-2222-4333-8444-555555555555"
prev=""
for a in "$@"; do
    case "$prev" in --session-id|--resume) sid="$a" ;; esac
    prev="$a"
done
printf '[{"type":"result","session_id":"%s","result":"done"}]\n' "$sid"
EOS
# termic: records its argv and whether the session transcript already held a
# user message at call time; prints the JSON the real one would.
cat > "$BIN/termic" <<'EOS'
#!/usr/bin/env bash
ready=no
[ -n "${STUB_TRANSCRIPT:-}" ] && grep -q '"type":"user"' "$STUB_TRANSCRIPT" 2>/dev/null && ready=yes
printf '%s user_line=%s\n' "$*" "$ready" >> "$STUB_TERMIC_LOG"
printf '{"task":{"name":"t","path":"/p","branch":"b"}}\n'
exit "${STUB_TERMIC_RC:-0}"
EOS
chmod +x "$BIN/claude" "$BIN/termic"

export CLAUDE_CONFIG_DIR="$WORK/cfg" HOME="$WORK/home"
mkdir -p "$CLAUDE_CONFIG_DIR/projects/-fake" "$HOME/.claude"
export STUB_CLAUDE_ARGS="$WORK/claude.args" STUB_CLAUDE_ENTRY="$WORK/claude.entry"
export STUB_TERMIC_LOG="$WORK/termic.log"

# ── scenario helpers ────────────────────────────────────────────────────────
# make_launcher TERMIC_ACTION [UUID_GENERATOR_WORKS=1] -> sets WT, LAUNCHER, PLANNED
make_launcher () {
    local action="$1" uuid_ok="${2:-1}"
    WT="$WORK/wt-$RANDOM"; mkdir -p "$WT"; WT="$(cd "$WT" && pwd -P)"
    : > "$LOG"
    PLANNED_FILE="$WORK/planned"; : > "$PLANNED_FILE"
    (
        set -u
        worktree_dir="$WT"; agent_type=claude; interactive=false
        creds_env_names=""; aws_role_readonly=""; aws_dir="$WT/.aitask-aws"
        permission_mode=auto; model=""; agent_settings=""; unsafe_bypass=false
        identifier=DVOPS-1; blocked_state=Blocked; lower_id=dvops-1
        prompt_file_out="$WT/.aitask-prompt.txt"; termic_action="$action"
        opencode_sandbox_config=""; opencode_config_file=""
        PATH="$BIN:$PATH"
        # shellcheck disable=SC1090
        . "$FUNCS"
        [ "$uuid_ok" = 1 ] || _new_uuid () { return 1; }
        _write_launcher
        printf '%s' "${planned_session_id:-}" > "$PLANNED_FILE"
    )
    LAUNCHER="$WT/.aitask-launch.sh"
    PLANNED="$(cat "$PLANNED_FILE")"
}

run_launcher () {
    export AITASK_CLEAN_ENV=1
    LAUNCH_RC=0
    ( cd "$WT" && PATH="$BIN:$PATH" bash "$LAUNCHER" >/dev/null 2>&1 ) || LAUNCH_RC=$?
}
claude_args () { cat "$STUB_CLAUDE_ARGS"; }

echo "== 1. fresh headless run: pre-assigned id, non-sdk entrypoint"
make_launcher new-task
check "planned session id is a UUID" bash -c "[[ '$PLANNED' =~ ^$UUID_RE\$ ]]"
check "launcher bakes the planned id" grep -q "^planned_sid=$PLANNED\$" "$LAUNCHER"
run_launcher
check "launcher exits 0" test "$LAUNCH_RC" = 0
check "claude got --session-id <planned>" grep -q -- "--session-id $PLANNED" "$STUB_CLAUDE_ARGS"
check "claude got -p" grep -q -- "^-p " "$STUB_CLAUDE_ARGS"
check "claude was not given --resume" test "$(claude_args | grep -c -- '--resume')" = 0
check "CLAUDE_CODE_ENTRYPOINT=ai-task reached claude" test "$(cat "$STUB_CLAUDE_ENTRY")" = ai-task
check "entrypoint is set inline on the command (launcher runs under env -i)" \
    grep -q '^CLAUDE_CODE_ENTRYPOINT=ai-task claude ' "$LAUNCHER"
check "session id recorded from the result" test "$(cat "$WT/.aitask-session-id")" = "$PLANNED"
check "launcher has no Termic code (registration is ai-task's job, at launch)" \
    test "$(grep -c -E 'termic_bin|termic new|termic_marker|"\$termic' "$LAUNCHER")" = 0

echo "== 2. re-running the launcher (resume/watch) continues the session"
run_launcher
check "claude got --resume <id>" grep -q -- "--resume $PLANNED" "$STUB_CLAUDE_ARGS"
check "claude was not given --session-id" test "$(claude_args | grep -c -- '--session-id')" = 0
check "entrypoint still set on the resume path" test "$(cat "$STUB_CLAUDE_ENTRY")" = ai-task

echo "== 3. session exists on disk but its id was never recorded"
make_launcher new-task
printf '%s\n' '{"type":"user"}' > "$CLAUDE_CONFIG_DIR/projects/-fake/$PLANNED.jsonl"
run_launcher
check "launcher continues it with --resume (claude rejects --session-id for an existing id)" \
    grep -q -- "--resume $PLANNED" "$STUB_CLAUDE_ARGS"
check "launcher does not pass --session-id" test "$(claude_args | grep -c -- '--session-id')" = 0

echo "== 4. no UUID generator: launcher omits --session-id"
make_launcher new-task 0
check "planned id is empty" test -z "$PLANNED"
check "warning emitted" grep -q "can't be pre-assigned" "$LOG"
run_launcher
check "claude was not given --session-id" test "$(claude_args | grep -c -- '--session-id')" = 0
check "claude still runs fresh with the entrypoint" test "$(cat "$STUB_CLAUDE_ENTRY")" = ai-task

# run_register INTERACTIVE PLANNED_ID [SESSION_FILE_CONTENT]  (-> REG_RC)
# Runs _register_termic against the stubs; `sleep` is a no-op when
# FAST_SLEEP=1 so the 30s timeout path is instant.
run_register () {
    local inter="$1" planned="$2" existing="${3:-}" agent="${4:-claude}"
    WT="$WORK/wt-$RANDOM"; mkdir -p "$WT"
    : > "$LOG"; : > "$STUB_TERMIC_LOG"
    [ -z "$existing" ] || printf '%s' "$existing" > "$WT/.aitask-session-id"
    REG_RC=0
    (
        set -eu
        worktree_dir="$WT"; agent_type="$agent"; interactive="$inter"; termic_action=new-task
        planned_session_id="$planned"
        PATH="$BIN:$PATH"
        # shellcheck disable=SC1090
        . "$FUNCS"
        _wait_for_session_id () { printf '%s' "99999999-0000-4000-8000-999999999999"; }
        if [ "${FAST_SLEEP:-0}" = 1 ] ; then sleep () { :; } ; fi
        _register_termic
    ) >/dev/null 2>&1 || REG_RC=$?
}

SID=aaaaaaaa-1111-4222-8333-444444444444
T="$CLAUDE_CONFIG_DIR/projects/-fake/$SID.jsonl"
export STUB_TRANSCRIPT="$T"

echo "== 5. registration waits for the first user message, then registers once"
rm -f "$T"
# queue-operation only at first (what claude -p writes at startup), the user
# line ~1.3s later (what it wrote 1.7-2.5s after start in real runs)
( printf '%s\n' '{"type":"queue-operation"}' > "$T"; sleep 1.3; printf '%s\n' '{"type":"user"}' >> "$T" ) &
writer=$!
run_register false "$SID"
wait "$writer"
check "register returns 0" test "$REG_RC" = 0
check "termic called exactly once" test "$(grep -c . "$STUB_TERMIC_LOG")" = 1
check "termic args: new --from <worktree> --resume <planned id>" \
    grep -q -- "^new --from $WT --resume $SID --output-format json " "$STUB_TERMIC_LOG"
check "termic was called only AFTER the transcript had a user line" grep -q 'user_line=yes$' "$STUB_TERMIC_LOG"

echo "== 6. a transcript without a user line never registers (times out, prints manual command)"
printf '%s\n' '{"type":"queue-operation"}' > "$T"
FAST_SLEEP=1 run_register false "$SID"
check "register still returns 0 (never fails the run)" test "$REG_RC" = 0
check "termic not called" test "$(grep -c . "$STUB_TERMIC_LOG")" = 0
check "manual retry command printed" grep -q "termic new --from $WT --resume $SID" "$LOG"

echo "== 7. continuing an existing session does not register a second task"
printf '%s\n' '{"type":"user"}' > "$T"
run_register false "$SID" "$SID"
check "termic not called" test "$(grep -c . "$STUB_TERMIC_LOG")" = 0
check "reason logged" grep -q "not registering a second task" "$LOG"

echo "== 8. failing termic: warning, never fatal"
printf '%s\n' '{"type":"user"}' > "$T"
STUB_TERMIC_RC=1 run_register false "$SID"
check "register returns 0" test "$REG_RC" = 0
check "retry command printed" grep -q "termic new --from $WT --resume $SID" "$LOG"

echo "== 9. no pre-assigned id: falls back to discovery, still waits for the transcript"
printf '%s\n' '{"type":"user"}' > "$CLAUDE_CONFIG_DIR/projects/-fake/99999999-0000-4000-8000-999999999999.jsonl"
STUB_TRANSCRIPT="$CLAUDE_CONFIG_DIR/projects/-fake/99999999-0000-4000-8000-999999999999.jsonl" run_register false ""
check "termic called with the discovered id" \
    grep -q -- "--resume 99999999-0000-4000-8000-999999999999 " "$STUB_TERMIC_LOG"

echo "== 10. interactive claude and opencode: unchanged (discover id, no transcript wait)"
rm -f "$T"
run_register true "$SID"
check "interactive claude registers with the discovered id" \
    grep -q -- "--resume 99999999-0000-4000-8000-999999999999 " "$STUB_TERMIC_LOG"
run_register false "$SID" "" opencode
check "opencode registers with the discovered id" \
    grep -q -- "--resume 99999999-0000-4000-8000-999999999999 " "$STUB_TERMIC_LOG"

echo "== 11. helpers"
check "_new_uuid prints a UUID" bash -c ". '$FUNCS'; [[ \"\$(_new_uuid)\" =~ ^$UUID_RE\$ ]]"
printf '%s\n' '{"type":"queue-operation"}' > "$T"
check "queue-operation-only transcript is not resumable" bash -c ". '$FUNCS'; ! _transcript_has_user_line $SID"
printf '%s\n' '{"type":"user"}' >> "$T"
check "transcript with a user line is resumable" bash -c ". '$FUNCS'; _transcript_has_user_line $SID"
check "non-UUID ids are rejected (the id is used in a glob)" bash -c ". '$FUNCS'; ! _transcript_has_user_line '*'"

echo
printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
