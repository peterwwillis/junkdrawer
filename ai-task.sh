#!/usr/bin/env bash
# ai-task.sh - list Linear issues ready for an AI to work on, and start one
#
# See README.md in this directory for full design notes and gotchas. Quick
# summary: `list` shows ready-to-work Linear issues matching your filters;
# `start <TICKET-ID>` creates an isolated git worktree for a specific one,
# optionally pre-authenticates read-only AWS credentials (AWS ReadOnly
# mode - opt-in via --aws-readonly-role ROLE / AITASK_AWS_ROLE_READONLY, or
# `aws-preauth` command), and launches an autonomous AI session in tmux -
# `claude` (default) or `opencode` (--agent-type opencode). The agent runs
# in a pristine login shell (env -i, HOME/TERM/LANG only) so nothing from
# your interactive terminal - exported credentials included - leaks in;
# --creds-loader / AITASK_CREDS_LOADER points at a script that gets sourced
# right before the agent launches to inject whatever credentials it needs.
#
# Each command's requirements are checked just for that command: `list`
# needs only the linear CLI + jq (and works outside a git repo); `start`
# additionally needs a git repo, git, tmux, and the CLI for whichever
# --agent-type is selected (claude or opencode); `aws-preauth` needs
# aws-sso, the AWS CLI, and jq, but never touches Linear.
set -eu
[ "${DEBUG:-0}" = "1" ] && set -x

SCRIPT="$(basename "$0")"
REPO_NAME="<repo>"   # placeholder; resolved by cmd_start (best-effort in _usage)

# Shared state: resolved options and start-pipeline artifacts live in
# script-scope globals (team, label, ..., worktree_dir, session, ...).
# Functions that set globals say so in their header comment; everything
# else takes explicit arguments.

_err ()  { printf "%s: Error: %s\n" "$SCRIPT" "$*" 1>&2 ; }
_info () { printf "%s: Info: %s\n" "$SCRIPT" "$*" 1>&2 ; }
_die ()  { _err "$@"; exit 1; }

# _require_cmd TOOL [HINT]
_require_cmd () {
    local tool="$1" hint="${2:-}"
    command -v "$tool" >/dev/null 2>&1 \
        || _die "Required command '$tool' not found in PATH${hint:+ - $hint}"
}

# Print the usage text (exits 0 on -h/--help; error paths go via
# _usage_error, which exits 1).
_usage () {
    # The usage text embeds $REPO_NAME (default worktree-root line). Resolve
    # it best-effort for display: use the already-detected repo if we have
    # one, else peek at the surrounding repo without requiring one (--help
    # must work anywhere), else keep the "<repo>" placeholder.
    local root url
    if [ "$REPO_NAME" = "<repo>" ] \
        && root="$(git rev-parse --show-toplevel 2>/dev/null)" \
        && url="$(git -C "$root" remote get-url origin 2>/dev/null)" ; then
        REPO_NAME="$(basename -s .git "$url")"
    fi
    cat <<EOUSAGE
Usage: $SCRIPT COMMAND [OPTIONS]

A command is required - there is no default action.

Commands:
  list                  List ready-to-work Linear issues matching your
                         filters. Read-only - doesn't touch git, tmux, or
                         Linear state. Exits 0 whether it finds zero or
                         many issues; only errors if the Linear query
                         itself fails (e.g. bad team, not authenticated).
  start TICKET-ID        Create a worktree + tmux session for the given
                         Linear issue (e.g. \`$SCRIPT start DVOPS-1234\`).
                         Pass --first instead of a ticket id to pick the
                         top match from the same filters \`list\` uses.
  aws-preauth OUTDIR ROLE  Mint read-only AWS credentials for every account
                          with a ':ROLE' profile into OUTDIR. Used
                          internally by AWS ReadOnly mode (opt-in -
                          see --aws-readonly-role); run it directly to
                          refresh an existing worktree's expired
                          credentials (they last about an hour - an AWS
                          platform limit, not configurable - see README.md).

"Ready to work" (for \`list\`) means: matches --state, in the --cycle, has
the --label, assigned to --assignee, optionally matching --priority, and
not blocked by any other open (non-completed/canceled) issue. Output is
one "IDENTIFIER<tab>title" line per match.

Filter options (used by \`list\`, and by \`start --first\`; every option
has an AITASK_<NAME> env var equivalent):
  --team TEAM               Linear team key to query. No hard default; if
                             unresolved you'll be prompted and it'll be
                             saved to your config file.
  --label LABEL              Linear label to filter on (default: aitask)
  --assignee ASSIGNEE        Assignee filter (default: self). Use "any"
                             for no assignee filter at all.
  --no-assignee               Only unassigned issues - overrides --assignee
  --state STATE              Issue state filter (default: unstarted)
  --cycle CYCLE               Cycle filter (default: active)
  --sort SORT                Sort order: priority or manual (default: priority)
  --priority N                Filter to issues with exactly this priority
                              (1-4; unset = no filter)

\`start\` options (every option has an AITASK_<NAME> env var equivalent):
  --first                     Pick the top match from the filter options
                              above instead of requiring a ticket id
  --worktree-root DIR         Parent directory for new worktrees
                              (default: \$HOME/.local/ai-task/worktrees/$REPO_NAME)
  --in-progress-state STATE   Exact Linear state name to set when starting
                              (default: "In Progress")
  --blocked-state STATE       Exact Linear state name if the agent gets stuck
                              (default: "Blocked")
  --agent-type TYPE            Which AI agent CLI to launch: "claude" or
                              "opencode" (default: claude)
  --permission-mode MODE      claude --permission-mode for the launched
                              session (default: auto). claude only -
                              ignored for --agent-type opencode, which
                              always runs with opencode's own --auto
                              (bypasses permission prompts not explicitly
                              denied - see README.md Safety; there's no
                              unattended-safe interactive mode to fall
                              back to for opencode).
  --model MODEL                Model for the launched session (default:
                              unset - whatever the agent's own
                              config/default resolves to). Format is
                              agent-specific:
                                claude:   an alias ("sonnet", "opus",
                                          "fable") or full model name
                                          (e.g. "claude-sonnet-5") - see
                                          README.md "Looking up model
                                          names"
                                opencode: "provider/model" (e.g.
                                          "anthropic/claude-sonnet-5") -
                                          run \`opencode models\` to list
                                          what's available
  --agent-settings PATH        Path to a settings/config JSON file for
                              the selected agent, merged in at runtime
                              (see README.md Safety - trusted input,
                              same as --prompt-file):
                                claude:   passed through verbatim as
                                          claude --settings PATH
                                opencode: merged into a generated
                                          OPENCODE_CONFIG (your file's
                                          settings plus the required
                                          opencode-sandbox plugin entry -
                                          see README.md)
  --creds-loader PATH         Path to a shell script sourced (not exec'd)
                              by the agent's shell right before the agent
                              launches, to inject credentials the task
                              needs (cloud tokens, registry logins, ...).
                              The agent starts from an empty environment
                              (env -i; only HOME/TERM/locale vars and the
                              login shell's profiles carry through), so
                              nothing leaks in from this terminal unless
                              you want it to - set it up here instead.
                              Trusted input, same as --prompt-file. Runs
                              inside the sandbox: if it needs network
                              access, add the hosts via --allowed-hosts.
                              AWS ReadOnly mode's own env exports are
                              applied after it, so they take precedence.
  --aws-readonly-role ROLE     AWS ReadOnly mode: name of the read-only
                               AWS role (the ':Role' suffix of your aws-sso
                               profiles, e.g. "ReadOnly-NoSecrets") to
                               pre-auth credentials for, plus AWS-specific
                               prompt/sandbox additions. Unset or empty (the
                               default) turns the feature off.
  --no-aws-readonly-role       Force AWS ReadOnly mode off, overriding
                               config/env - use this when your config file
                               sets a role but this task needs no AWS
                               access
  --allowed-hosts HOSTS       Comma-separated extra sandbox network
                              allowlist entries
  --termic ACTION            After the tmux + agent are up, register the
                              just-created worktree and AI agent session as
                              a new task in the Termic app (runs
                              \`termic new --from <worktree> --resume
                              <session-id>\`). Currently the only ACTION is
                              \`new-task\`. Off by default; set AITASK_TERMIC
                              in your config file to make it the default
                              for a project. The script auto-discovers the
                              agent's session id:
                                claude:   \`claude agents --json --cwd
                                          <worktree>\`
                                opencode: \`opencode session list --format
                                          json\` (filtered by directory)
                              with a 30s polling budget. On any failure
                              (termic not installed, session not yet
                              registered, Termic CLI disabled, ...) the
                              script warns and continues - the tmux session
                              is already usable regardless.
  --prompt-file PATH          Use this file as the prompt instead of the
                              built-in template (supports {{IDENTIFIER}},
                              {{TITLE}}, {{URL}}, {{DESCRIPTION}},
                              {{BLOCKED_STATE}} placeholders)
  --prompt-extra TEXT         Extra text appended to the prompt
  -n, --dry-run                Show what would happen; don't touch git,
                              Linear, or tmux

  -h, --help                  This screen

Environment variables: AITASK_TEAM, AITASK_LABEL, AITASK_ASSIGNEE,
AITASK_NO_ASSIGNEE, AITASK_STATE, AITASK_CYCLE, AITASK_SORT, AITASK_PRIORITY,
AITASK_WORKTREE_ROOT, AITASK_IN_PROGRESS_STATE, AITASK_BLOCKED_STATE,
AITASK_AGENT_TYPE, AITASK_PERMISSION_MODE, AITASK_MODEL, AITASK_AGENT_SETTINGS,
AITASK_AWS_ROLE_READONLY, AITASK_CREDS_LOADER, AITASK_ALLOWED_HOSTS, AITASK_TERMIC,
AITASK_PROMPT_FILE, AITASK_PROMPT_EXTRA.

AITASK_TEAM falls back to linear-cli's own LINEAR_TEAM_ID; AITASK_SORT
falls back to LINEAR_ISSUE_SORT (see linear-cli's own configuration docs).

Config file: sourced as a plain shell script (set the same AITASK_<NAME>
variables shown above). Name it either \`ai-task.conf\` or \`.ai-taskrc\`
(rc-file style) - both are checked, at both scopes, loaded in order so
later files win:
  \$HOME/.config/ai-task/ai-task.conf
  \$HOME/.ai-taskrc
  \$(pwd)/ai-task.conf
  \$(pwd)/.ai-taskrc                    (project-local overrides, e.g. repo root)
An explicit env var you set for this invocation always wins over anything
a config file sets for the same name. See README.md for worktree-root
conventions used by other tools (Termic, Conductor, opencode, ...) and how
to point --worktree-root at one of them if you'd rather share that layout.
EOUSAGE
}

# Error-path usage: print the help text and exit non-zero.
_usage_error () {
    _usage
    exit 1
}

# _require_value OPT REMAINING_ARGC
#
# Call right after shifting off a value-taking flag; REMAINING_ARGC is the
# caller's $# at that point. Dies with a clean usage error if no value
# argument remains (previously a trailing "--team" crashed with a cryptic
# "unbound variable" under set -u).
_require_value () {
    [ "$2" -gt 0 ] || { _err "Missing value for $1"; _usage_error; }
}

# _cmd_aws_preauth OUTDIR ROLE
#
# Mints short-lived STS credentials for the given read-only role name
# (the ':Role' suffix of your aws-sso profiles, e.g. 'ReadOnly-NoSecrets')
# in every AWS account you have access to (via aws-sso), and writes them as an
# isolated, plain-static-credential AWS config/credentials file pair under
# OUTDIR. These files never reference aws-sso or credential_process - they're
# just static keys, so a sandboxed session using them has no path to
# escalate to a different role even if it tries.
#
# Credentials expire in about an hour. That's an AWS platform limit for
# this credential type (SSO-federated / role-chained session credentials
# are always capped at 1hr, regardless of the permission set's configured
# Session Duration) - not something this script, aws-sso, or any client can
# configure around. Just re-run `ai-task.sh aws-preauth OUTDIR ROLE` to refresh.
#
# `ai-task.sh start` calls this for you at worktree-creation time whenever
# a read-only AWS role is configured (AITASK_AWS_ROLE_READONLY /
# --aws-readonly-role; off by default). Run it
# directly to refresh an existing worktree's expired credentials
# without recreating the task. Never run it from inside an ai-task session
# itself - it's the trusted side of the boundary, and needs your own valid
# `aws-sso login` session to work.
_cmd_aws_preauth () {
    local outdir="$1" role="$2" credfile conffile readme region profiles count profile
    local creds_json access_key secret_key session_token expiration

    [ -n "$role" ] || _die "AWS role name must not be empty"
    _require_cmd aws-sso
    _require_cmd aws "needed for 'aws configure list-profiles'"
    _require_cmd jq

    mkdir -p "$outdir"
    credfile="$outdir/credentials"
    conffile="$outdir/config"
    readme="$outdir/README.md"
    : > "$credfile"
    : > "$conffile"
    chmod 600 "$credfile" "$conffile"

    region="$(awk '/DefaultRegion/{print $2}' ~/.config/aws-sso/config.yaml 2>/dev/null)"
    region="${region:-us-east-1}"

    profiles="$(aws configure list-profiles | grep ":$role\$" || true)"
    if [ -z "$profiles" ] ; then
        _err "No profiles ending in ':$role' found."
        _die "Try: aws-sso login && aws-sso setup profiles --force"
    fi

    # shellcheck disable=SC2016  # literal backticks are README prose, not expansion
    {
        printf '# Read-only AWS access for this ai-task session\n\n'
        printf 'This session has READ-ONLY AWS access only, scoped per account via the\n'
        printf 'profiles below. There is no admin/write path available here: aws-sso is\n'
        printf 'not usable in this sandbox (its config/cache is blocked), and these\n'
        printf 'profile files contain only short-lived static credentials - no\n'
        # shellcheck disable=SC2016
        printf '`credential_process`, no reference to aws-sso at all.\n\n'
        printf 'Credentials expire in about an hour (an AWS platform limit for this\n'
        printf 'credential type, not something configurable - see README.md). Re-run\n'
        # shellcheck disable=SC2016
        printf '`ai-task.sh aws-preauth %s %s` to refresh.\n\n' "$outdir" "$role"
        # shellcheck disable=SC2016
        printf 'Before running AWS or terraform commands in a given\n'
        # shellcheck disable=SC2016
        printf '`env/aws/<tenant>/...` directory, set the matching profile first, e.g.:\n\n'
        printf '    export AWS_PROFILE="<tenant>:%s"\n\n' "$role"
        printf 'Available profiles:\n'
    } > "$readme"

    count=0
    while IFS= read -r profile ; do
        [ -n "$profile" ] || continue
        _info "Minting short-lived credentials for '$profile'..."
        # Capture stdout only: aws-sso's stderr (warnings, errors) passes
        # straight through to the user instead of being folded into the JSON
        # and corrupting the jq parses below.
        creds_json="$(aws-sso process -p "$profile")" || {
            _err "Failed to get credentials for '$profile' (see aws-sso's error above)."
            _err "Is your aws-sso session valid? Try: aws-sso login"
            _die "A partial credentials file may exist at $credfile - re-run to rewrite it from scratch."
        }
        access_key="$(printf '%s' "$creds_json" | jq -r .AccessKeyId)"
        secret_key="$(printf '%s' "$creds_json" | jq -r .SecretAccessKey)"
        session_token="$(printf '%s' "$creds_json" | jq -r .SessionToken)"
        expiration="$(printf '%s' "$creds_json" | jq -r .Expiration)"

        {
            printf '[%s]\n' "$profile"
            printf 'aws_access_key_id = %s\n' "$access_key"
            printf 'aws_secret_access_key = %s\n' "$secret_key"
            printf 'aws_session_token = %s\n\n' "$session_token"
        } >> "$credfile"

        {
            printf '[profile %s]\n' "$profile"
            printf 'region = %s\n\n' "$region"
        } >> "$conffile"

        printf '  - %s (expires %s)\n' "$profile" "$expiration" >> "$readme"

        _info "  -> expires $expiration"
        count=$((count + 1))
    done <<< "$profiles"

    # shellcheck disable=SC2016  # literal backticks are README prose, not expansion
    {
        printf '\n`make tfsh-apply` / `terraform apply` will fail with an AWS permission\n'
        printf 'error in this environment by design - this session can only plan and\n'
        printf 'investigate, not apply. If a task needs an actual apply, describe what\n'
        printf 'needs to change (e.g. in the PR description) - a human applies it via\n'
        printf 'the existing `/terraform-apply` PR-comment workflow.\n'
    } >> "$readme"

    _info "Wrote $count read-only profile(s) to $outdir"
}

# _get_claude_session_id WORKTREE_DIR
#
# Prints the interactive claude session id registered under WORKTREE_DIR
# (most recently started), or empty if none. `claude agents --json --cwd`
# scopes the listing to background and interactive sessions whose working
# directory is the given worktree. We filter to kind == "interactive"
# because this script runs `claude` directly (not as a background agent).
_get_claude_session_id () {
    local worktree_dir="$1"
    claude agents --json --cwd "$worktree_dir" 2>/dev/null \
        | jq -r '[.[] | select(.kind == "interactive")]
                 | sort_by(.startedAt) | reverse
                 | .[0].sessionId // empty'
}

# _get_opencode_session_id WORKTREE_DIR
#
# Prints the opencode session id whose `directory` is WORKTREE_DIR (most
# recently updated), or empty if none. `opencode session list --format
# json` enumerates every session the opencode DB knows about; we filter
# by the directory the agent was started in. The script runs opencode
# non-interactively (`opencode run --auto ...`), which still creates a
# session row in the DB.
_get_opencode_session_id () {
    local worktree_dir="$1"
    opencode session list --format json 2>/dev/null \
        | jq -r --arg d "$worktree_dir" \
            '[.[] | select(.directory == $d)]
             | sort_by(.updated) | reverse
             | .[0].id // empty'
}

# _wait_for_session_id AGENT_TYPE WORKTREE_DIR
#
# Polls the agent-specific lookup for up to 30 seconds (1s interval),
# printing the first non-empty result. Empty + non-zero return means
# "timed out". Both agent CLIs register their session lazily after the
# process spawns, so a fresh launch needs a moment to appear.
_wait_for_session_id () {
    local agent_type="$1" worktree_dir="$2"
    local session_id attempt
    for (( attempt = 1 ; attempt <= 30 ; attempt++ )) ; do
        if [ "$agent_type" = "claude" ] ; then
            session_id="$(_get_claude_session_id "$worktree_dir")"
        else
            session_id="$(_get_opencode_session_id "$worktree_dir")"
        fi
        [ -n "$session_id" ] && { printf '%s' "$session_id"; return 0; }
        sleep 1
    done
    return 1
}

# _do_termic_new_task WORKTREE_DIR AGENT_TYPE
#
# Opt-in post-launch hook: register the just-created worktree + AI agent
# session as a new task in the Termic app. Runs:
#
#     termic new --from WORKTREE_DIR --resume AGENT_SESSION_ID
#
# Session id discovery is agent-specific (see helpers above). Failures
# here are warnings, not errors - the tmux session and agent are already
# running by this point, so a missing Termic install or a slow agent
# lookup shouldn't break an otherwise-successful run. The user is told
# the exact manual command to retry on their own.
_do_termic_new_task () {
    local worktree_dir="$1" agent_type="$2"
    local session_id termic_json

    _info "Creating Termic task from $worktree_dir..."

    if ! command -v termic >/dev/null 2>&1 ; then
        _err "termic not found in PATH - skipping Termic task creation. The tmux session and agent are still running."
        return 0
    fi

    _info "Waiting for $agent_type session to register (up to 30s)..."
    if ! session_id="$(_wait_for_session_id "$agent_type" "$worktree_dir")" ; then
        _err "Couldn't auto-discover $agent_type session id for $worktree_dir after 30s."
        _err "The tmux session and agent are still running. You can wire this up manually:"
        _err "  termic new --from $worktree_dir --resume <session-id>"
        return 0
    fi
    _info "Discovered session id: $session_id"

    # Capture stdout only - termic's stderr (warnings/progress) passes
    # through to the user untouched. Folding it into the JSON would corrupt
    # the jq parses below on any warning, killing the script even though
    # the task was actually created.
    if ! termic_json="$(termic new --from "$worktree_dir" --resume "$session_id" --output-format json)" ; then
        _err "termic new failed - the tmux session is still running. You can retry manually:"
        _err "  termic new --from $worktree_dir --resume $session_id"
        return 0
    fi

    # Termic's --output-format json contract is additive, so defensive
    # // empty fallbacks on every field we echo.
    local task_name task_path task_branch
    task_name="$(printf '%s' "$termic_json" | jq -r '.task.name // "<unknown>"')"
    task_path="$(printf '%s' "$termic_json" | jq -r '.task.path // "<unknown>"')"
    task_branch="$(printf '%s' "$termic_json" | jq -r '.task.branch // "<unknown>"')"
    _info "Termic task created: $task_name (branch $task_branch, path $task_path)"
    _info "Open with: termic open $task_name"
}

# _detect_main_branch ROOTDIR -> prints origin's default branch name (e.g.
# "main", "master", "trunk"). Tries the cheap local answer first
# (refs/remotes/origin/HEAD, set by `git clone`/`git remote set-head`); if
# that's missing (e.g. a fresh clone that never fetched HEAD), asks the
# remote directly via `git ls-remote --symref`, which requires no local
# state and doesn't mutate anything. Falls back to "main" only if both fail.
# Only called from cmd_start - the ls-remote fallback is a network call, and
# `list`/`aws-preauth` must not pay for it.
_detect_main_branch () {
    local rootdir="$1" ref
    ref="$(git -C "$rootdir" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)" \
        && { printf '%s' "${ref#origin/}"; return; }
    ref="$(git -C "$rootdir" ls-remote --symref origin HEAD 2>/dev/null \
        | awk '/^ref:/{print $2}' | sed 's#refs/heads/##')"
    [ -n "$ref" ] && { printf '%s' "$ref"; return; }
    printf 'main'
}

# ── Option / env / config resolution helpers ────────────────────────────────
#
# Precedence (highest wins): --flag > env var you set for this invocation >
# config file > linear-cli's own env vars (team/sort only) > hardcoded
# default. We snapshot the "real" env vars (_snapshot_env) BEFORE sourcing
# config files, so a persisted config can't clobber something you explicitly
# exported just for this run.

_AITASK_VARS="AITASK_TEAM AITASK_LABEL AITASK_ASSIGNEE AITASK_NO_ASSIGNEE AITASK_STATE AITASK_CYCLE
AITASK_SORT AITASK_PRIORITY AITASK_WORKTREE_ROOT AITASK_IN_PROGRESS_STATE AITASK_BLOCKED_STATE
AITASK_AGENT_TYPE AITASK_PERMISSION_MODE AITASK_MODEL AITASK_AGENT_SETTINGS AITASK_AWS_ROLE_READONLY
AITASK_CREDS_LOADER AITASK_ALLOWED_HOSTS AITASK_TERMIC AITASK_PROMPT_FILE AITASK_PROMPT_EXTRA"

# Snapshot the user's real AITASK_* env values into orig_<VAR> before any
# config file is sourced (see precedence note above).
_snapshot_env () {
    local v
    for v in $_AITASK_VARS ; do
        eval "orig_$v=\"\${$v:-}\""
    done
}

# Loads shell script into current session if it exists
# shellcheck source=/dev/null
_loadconf () { [ ! -e "$1" ] || . "$1" ; }

# _resolve VAR CLIVAL DEFAULT [FALLBACK_ENV_VAR ...]
_resolve () {
    local var="$1" cli="$2" default="$3" orig="orig_$1" fb
    shift 3
    [ -z "$cli" ] || { printf '%s' "$cli"; return; }
    [ -z "${!orig:-}" ] || { printf '%s' "${!orig}"; return; }
    [ -z "${!var:-}" ] || { printf '%s' "${!var}"; return; }
    for fb in "$@" ; do
        [ -z "${!fb:-}" ] || { printf '%s' "${!fb}"; return; }
    done
    printf '%s' "$default"
}

# _query_ready_issues -> prints a JSON array of matching, unblocked issues
# (per the resolved team/label/state/cycle/assignee_args/priority/sort) to
# stdout. Used by both `list` and `start --first`, so both pick from
# exactly the same candidate set. An issue is "blocked" if any
# inverseRelation of type "blocks" points at an issue that is not
# completed/canceled (i.e. still open).
_query_ready_issues () {
    local query_json
    query_json="$(linear issue query --json \
        --team "$team" \
        --label "$label" \
        --state "$state" \
        --cycle "$cycle" \
        "${assignee_args[@]}" \
        --sort "$sort" \
        --limit 50)"
    printf '%s' "$query_json" | jq -c --arg priority "$priority" '
        [.nodes[] | select(
            ($priority == "" or (.priority | tostring) == $priority)
            and ([.inverseRelations.nodes[]?
                | select(.type == "blocks"
                    and .issue.state.type != "completed"
                    and .issue.state.type != "canceled")
             ] | length) == 0
        )]
    '
}

# ── list command ─────────────────────────────────────────────────────────────

cmd_list () {
    _info "Querying Linear: team=$team label=$label state=$state cycle=$cycle $assignee_desc sort=$sort${priority:+ priority=$priority}"
    local matches_json count
    matches_json="$(_query_ready_issues)"

    count="$(printf '%s' "$matches_json" | jq 'length' 2>/dev/null)"
    case "$count" in
        ''|*[!0-9]*) _die "Unexpected output from 'linear issue query' - couldn't parse the result. Is your linear CLI up to date?" ;;
    esac
    if [ "$count" -eq 0 ] ; then
        _info "No ready issues found for team $team (checked state=$state, cycle=$cycle, label=$label, $assignee_desc${priority:+, priority=$priority}, unblocked)."
        return 0
    fi
    printf '%s' "$matches_json" | jq -r '.[] | "\(.identifier)\t\(.title)"'
}

# ── start command ────────────────────────────────────────────────────────────

# Sets ticket_id from --first or validates the bare positional.
_pick_first_ticket () {
    if [ "$first" = "1" ] ; then
        [ -z "$ticket_id" ] || _die "Can't pass both a ticket id ('$ticket_id') and --first."
        _info "Querying Linear for the top match: team=$team label=$label state=$state cycle=$cycle $assignee_desc sort=$sort${priority:+ priority=$priority}"
        local matches_json
        matches_json="$(_query_ready_issues)"
        ticket_id="$(printf '%s' "$matches_json" | jq -r 'first | .identifier // empty')"
        [ -n "$ticket_id" ] || _die "No ready issues found matching filters - nothing to start with --first."
    else
        [ -n "$ticket_id" ] || _die "Usage: $SCRIPT start <TICKET-ID> [OPTIONS] (or pass --first to pick the top match automatically)"
    fi
}

# Validates the trusted-input file options up front, before anything is
# created or Linear state is touched. Sets nothing.
_validate_start_inputs () {
    if [ -n "$agent_settings" ] ; then
        [ -r "$agent_settings" ] || _die "--agent-settings '$agent_settings' not found or not readable"
        jq empty "$agent_settings" 2>/dev/null || _die "--agent-settings '$agent_settings' is not valid JSON"
        if [ "$agent_type" = "opencode" ] ; then
            # The opencode merge does `.plugin = ...`, which only works on a
            # top-level JSON object - an array/string file would otherwise
            # slip past the validity check and blow up mid-pipeline, after
            # the worktree exists and the issue is already In Progress.
            jq -e 'type == "object"' "$agent_settings" >/dev/null 2>&1 \
                || _die "--agent-settings '$agent_settings' must be a JSON object at the top level"
        fi
    fi
    if [ -n "$creds_loader" ] ; then
        [ -r "$creds_loader" ] || _die "--creds-loader '$creds_loader' not found or not readable"
    fi
    if [ -n "$prompt_file" ] ; then
        [ -r "$prompt_file" ] || _die "--prompt-file '$prompt_file' not found or not readable"
    fi
}

# _fetch_issue TICKET-ID
#
# Sets globals: identifier, title, url, description, branch.
_fetch_issue () {
    local ticket="$1" issue_json
    issue_json="$(linear issue view "$ticket" --json)" || _die "Could not fetch issue '$ticket' from Linear."
    identifier="$(printf '%s' "$issue_json" | jq -r '.identifier')"
    title="$(printf '%s' "$issue_json" | jq -r '.title')"
    url="$(printf '%s' "$issue_json" | jq -r '.url')"
    description="$(printf '%s' "$issue_json" | jq -r '.description // ""')"
    branch="$(printf '%s' "$issue_json" | jq -r '.branchName')"
    [ -n "$identifier" ] && [ "$identifier" != "null" ] \
        || _die "Linear returned no identifier for '$ticket' - aborting."
    # A null branchName would otherwise become a git branch literally named
    # "null".
    [ -n "$branch" ] && [ "$branch" != "null" ] \
        || _die "Linear issue '$ticket' has no branch name (.branchName is empty/null) - can't create a worktree."
}

# Sets globals: lower_id, worktree_dir, session.
_compute_paths () {
    lower_id="$(printf '%s' "$identifier" | tr '[:upper:]' '[:lower:]')"
    worktree_dir="$worktree_root/$lower_id"
    session="aitask-$lower_id"
}

_report_plan () {
    _info "Starting $identifier: $title"
    _info "  $url"
    _info "Branch:    $branch"
    _info "Worktree:  $worktree_dir"
    _info "Session:   $session"
    _info "Agent:     $agent_type"
    _info "Model:     ${model:-<agent default>}"
    _info "AWS ReadOnly role: ${aws_role_readonly:-<off>}"
    _info "Creds loader: ${creds_loader:-<none>}"
}

# Dies (with cleanup hints) on conflicts that would make the run fail later:
# an existing worktree dir, an existing worktree branch, or an existing tmux
# session. Sets nothing.
_preflight_conflicts () {
    if [ -e "$worktree_dir" ] ; then
        _err "Worktree directory already exists: $worktree_dir"
        _die "If the previous task for $identifier is done: git -C \"$ROOTDIR\" worktree remove \"$worktree_dir\" - then re-run. (If its tmux session is still up: tmux attach -t $session)"
    fi
    # The dir may be gone while the branch lingers (e.g. the worktree was
    # deleted without `git worktree remove`, or the branch was pushed from
    # elsewhere). `git worktree add -b` would fail here with a cryptic git
    # error, so check proactively.
    if git -C "$ROOTDIR" show-ref --verify --quiet "refs/heads/$branch" ; then
        _err "Branch '$branch' already exists in $REPO_NAME, so the worktree branch can't be created."
        _die "If it's from a finished task: git -C \"$ROOTDIR\" branch -D \"$branch\" - then re-run. (Also consider: git worktree prune)"
    fi
    if tmux has-session -t "$session" 2>/dev/null ; then
        _die "tmux session '$session' already exists. Attach with: tmux attach -t $session"
    fi
}

_create_worktree () {
    _info "Fetching latest origin/$MAIN_BRANCH..."
    git -C "$ROOTDIR" fetch origin "$MAIN_BRANCH"

    _info "Creating worktree..."
    mkdir -p "$worktree_root"
    git -C "$ROOTDIR" worktree add -b "$branch" "$worktree_dir" "origin/$MAIN_BRANCH"
}

# Sets global: aws_dir. No-op unless AWS ReadOnly mode is on.
_setup_aws_readonly () {
    [ -n "$aws_role_readonly" ] || return 0
    aws_dir="$worktree_dir/.aitask-aws"
    _info "Minting read-only AWS credentials for the sandboxed session..."
    _cmd_aws_preauth "$aws_dir" "$aws_role_readonly"
}

# ── Sandbox config ───────────────────────────────────────────────────────────
# hosts/cred_files are shared between both agent backends - only the JSON
# shape each one wants differs (see README.md "Safety" for what each
# backend's isolation mechanism actually is and its known gaps).

# Sets globals: hosts, hosts_json, cred_files, cred_files_json, deny_read_json.
_build_sandbox_allowlists () {
    hosts=(github.com api.github.com raw.githubusercontent.com linear.app api.linear.app)
    [ -z "$aws_role_readonly" ] || hosts+=("*.amazonaws.com" "169.254.169.254" "169.254.170.2")
    if [ -n "$allowed_hosts_extra" ] ; then
        local extra_hosts
        IFS=',' read -r -a extra_hosts <<< "$allowed_hosts_extra"
        hosts+=("${extra_hosts[@]}")
    fi
    hosts_json="$(printf '%s\n' "${hosts[@]}" | jq -R . | jq -s .)"

    # Literal ~ is intentional: the sandbox consumers expand it themselves;
    # expanding it here would leak the absolute home path into generated
    # config files.
    # shellcheck disable=SC2088
    cred_files=("~/.ssh")
    # shellcheck disable=SC2088
    [ -z "$aws_role_readonly" ] || cred_files+=("~/.config/aws-sso" "~/.aws")

    cred_files_json="$(printf '%s\n' "${cred_files[@]}" | jq -R '{path: ., mode: "deny"}' | jq -s .)"
    deny_read_json="$(printf '%s\n' "${cred_files[@]}" | jq -R . | jq -s .)"
}

_write_claude_sandbox_config () {
    _info "Writing sandbox config for the worktree (.claude/settings.local.json)..."
    mkdir -p "$worktree_dir/.claude"
    jq -n --argjson hosts "$hosts_json" --argjson credfiles "$cred_files_json" '
    {
      sandbox: {
        enabled: true,
        credentials: { files: $credfiles },
        network: { allowedHosts: $hosts }
      }
    }' > "$worktree_dir/.claude/settings.local.json"
    # NOTE: the sandbox.* schema above is a best-effort guess grounded in this
    # session's own observed sandbox config, not a confirmed schema from
    # official Claude Code docs - verify empirically before relying on it as a
    # hard boundary. See README.md "Gotchas" for what IS empirically verified.
}

# Sets globals: opencode_sandbox_config, opencode_config_file.
_write_opencode_sandbox_config () {
    # opencode: no built-in equivalent to Claude Code's sandbox, so isolation
    # comes from the third-party `opencode-sandbox` plugin (wraps
    # @anthropic-ai/sandbox-runtime - the same seatbelt/bubblewrap primitive
    # Claude Code itself uses). It fails OPEN if it can't initialize - see
    # README.md "Safety" for that caveat and what is/isn't covered.
    _info "Writing opencode sandbox config for the worktree..."
    opencode_sandbox_config="$(jq -nc --argjson domains "$hosts_json" --argjson denyread "$deny_read_json" '
    {
      filesystem: { denyRead: $denyread },
      network: { allowedDomains: $domains }
    }')"

    # opencode-sandbox needs "opencode-sandbox" in the resolved config's
    # `plugin` array to load at all. Never edit the worktree's own (possibly
    # committed) opencode.json/.opencode/opencode.json in place - that risks
    # accidentally shipping our forced plugin in the task's own PR. Instead
    # read any user-supplied --agent-settings as a starting point (already
    # validated as a JSON object above) and write the merged result to our own
    # generated file, pointed at via OPENCODE_CONFIG - which loads *alongside*
    # (not instead of) the project's own opencode.json.
    opencode_config_file="$worktree_dir/.aitask-opencode-config.json"
    local base_config="{}"
    [ -z "$agent_settings" ] || base_config="$(cat "$agent_settings")"
    printf '%s' "$base_config" | jq '.plugin = ((.plugin // []) + ["opencode-sandbox"] | unique)' > "$opencode_config_file"
}

_write_sandbox_config () {
    _build_sandbox_allowlists
    if [ "$agent_type" = "claude" ] ; then
        _write_claude_sandbox_config
    else
        _write_opencode_sandbox_config
    fi
}

# ── Prompt ───────────────────────────────────────────────────────────────────

# Builds the base prompt into global $prompt: either the user-supplied
# template (with placeholders substituted) or the built-in default.
_build_base_prompt () {
    if [ -n "$prompt_file" ] ; then
        # Readability was validated up front in _validate_start_inputs.
        prompt="$(cat "$prompt_file")"
        # Plain string substitution only - the file is never sourced/eval'd.
        prompt="${prompt//\{\{IDENTIFIER\}\}/$identifier}"
        prompt="${prompt//\{\{TITLE\}\}/$title}"
        prompt="${prompt//\{\{URL\}\}/$url}"
        prompt="${prompt//\{\{DESCRIPTION\}\}/$description}"
        prompt="${prompt//\{\{BLOCKED_STATE\}\}/$blocked_state}"
    else
        # Note: read -d '' (rather than prompt="$(cat <<EOP ... )") avoids a
        # bash quirk where an apostrophe inside a heredoc nested in $(...)
        # breaks parsing.
        read -r -d '' prompt <<EOP || true
Work on Linear issue $identifier: $title

$url

<description>
$description
</description>

You're working autonomously and unattended in an isolated git worktree -
nobody is watching this session in real time, so don't wait for
confirmation on ordinary decisions. Plan your approach before making
changes. If the ticket itself is ambiguous about what's wanted, say so in
a Linear comment (see below) and use your best judgment rather than
stalling.

Post a Linear comment (\`linear issue comment add $identifier -b "..."\`)
at each of these milestones:

1. When you start: a short comment noting you've begun and your plan.
2. If you hit something this session genuinely can't do because of its
   restricted scope or permissions: keep working on everything else you
   can first, note the gap clearly in the PR description (step 3), then
   comment explaining exactly what's needed, move the ticket to
   "$blocked_state" (\`linear issue update $identifier --state "$blocked_state"\`),
   and stop.
3. When finished (fully, or as far as this session could get): commit
   your work and open a PR with \`gh pr create\` referencing this ticket
   with "ref $identifier" in the PR body (not a closing keyword like
   "fixes"). No test-plan checklist, no "Generated with Claude Code"
   line. Then post a final Linear comment with the PR link.

Never force-push, never run destructive git operations.
EOP
    fi
}

_append_aws_prompt () {
    [ -n "$aws_role_readonly" ] || return 0
    prompt="$prompt

AWS ReadOnly mode is on for this repo/session (role: $aws_role_readonly):
- AWS access is READ-ONLY only - see .aitask-aws/README.md for the
  available profiles and how to select one (set AWS_PROFILE before
  running AWS/terraform commands in a given env/aws/<tenant>/ directory).
  \`terraform apply\`/\`make tfsh-apply\` will fail here by design - this
  session can plan and investigate, not apply.
- Your AWS credentials expire after about an hour (an AWS platform limit -
  not something you can extend or work around). If AWS/terraform calls
  start failing with an expired/invalid-token error, that's what happened -
  it's expected for a longer-running session, not a bug to fix. Do NOT try
  \`aws-sso login\` or any other re-auth yourself - it's intentionally
  unavailable in this sandbox and won't work. Instead: keep making progress
  on anything that doesn't need AWS, and post a Linear comment asking the
  user to run \`ai-task.sh aws-preauth <this worktree>/.aitask-aws $aws_role_readonly\`
  to refresh your credentials, then continue once they confirm.
- Follow this repo's CLAUDE.md and .claude/rules/, especially the
  terraformsh/make wrapper workflow - never run terraform directly."
}

_append_extra_prompt () {
    [ -n "$prompt_extra" ] || return 0
    prompt="$prompt

Additional instructions:
$prompt_extra"
}

# Sets global: prompt_file_out.
_write_prompt_file () {
    prompt_file_out="$worktree_dir/.aitask-prompt.txt"
    printf '%s' "$prompt" > "$prompt_file_out"
}

# Sets global: launcher_file.
_write_launcher () {
    launcher_file="$worktree_dir/.aitask-launch.sh"
    {
        printf '#!/usr/bin/env bash\n'
        # The pane itself can't be started with a clean env portably (tmux
        # mangles multi-word new-session commands differently across
        # versions), so the launcher re-execs itself under `env -i bash -l`
        # instead: agent ends up in a pristine login shell regardless of
        # whatever the launching terminal had exported. Only HOME (needed),
        # TERM (needed by agent CLIs; tmux default if unset) and locale vars
        # pass through; PATH is rebuilt by /etc/profile + ~/.bash_profile.
        # NOTE: if your login profiles export credentials, they come back by
        # design - this isolates from the session's shell, not from your
        # machine's startup files.
        cat <<'EOLAUNCHER'
if [ "${AITASK_CLEAN_ENV:-}" != "1" ] ; then
    clean_env=(env -i HOME="$HOME" AITASK_CLEAN_ENV=1 "TERM=${TERM:-xterm-256color}")
    [ -z "${LANG:-}" ] || clean_env+=("LANG=$LANG")
    [ -z "${LC_ALL:-}" ] || clean_env+=("LC_ALL=$LC_ALL")
    exec "${clean_env[@]}" bash -l "$0"
fi
EOLAUNCHER
        printf 'cd %q\n' "$worktree_dir"
        # Loader runs before ai-task's own exports below, so the sandbox's AWS
        # config pinning / OPENCODE_* vars always have the final say.
        [ -z "$creds_loader" ] || printf '. %q\n' "$creds_loader"
        if [ -n "$aws_role_readonly" ] ; then
            printf 'unset AWS_PROFILE\n'
            printf 'export AWS_CONFIG_FILE=%q\n' "$aws_dir/config"
            printf 'export AWS_SHARED_CREDENTIALS_FILE=%q\n' "$aws_dir/credentials"
        fi
        if [ "$agent_type" = "claude" ] ; then
            printf 'exec claude'
            printf ' --permission-mode %q' "$permission_mode"
            [ -z "$model" ] || printf ' --model %q' "$model"
            [ -z "$agent_settings" ] || printf ' --settings %q' "$agent_settings"
            # shellcheck disable=SC2016  # "$(cat ...)" must expand when the agent runs, not now
            printf ' "$(cat %q)"\n' "$prompt_file_out"
        else
            # --auto bypasses any opencode permission prompt not explicitly
            # denied - opencode's own docs call this "dangerous". There's no
            # smart auto-approve-but-pause-on-risky-stuff mode to fall back to
            # like claude's default, and an unattended detached tmux session
            # would otherwise hang forever on the first interactive prompt. See
            # README.md "Safety".
            printf 'export OPENCODE_SANDBOX_CONFIG=%q\n' "$opencode_sandbox_config"
            printf 'export OPENCODE_CONFIG=%q\n' "$opencode_config_file"
            printf 'exec opencode run --auto'
            [ -z "$model" ] || printf ' --model %q' "$model"
            # shellcheck disable=SC2016  # "$(cat ...)" must expand when the agent runs, not now
            printf ' "$(cat %q)"\n' "$prompt_file_out"
        fi
    } > "$launcher_file"
    chmod +x "$launcher_file"
}

_mark_in_progress () {
    _info "Marking $identifier as '$in_progress_state' in Linear..."
    linear issue update "$identifier" --state "$in_progress_state"
}

_launch_tmux () {
    _info "Starting tmux session '$session'..."
    tmux new-session -d -s "$session" -c "$worktree_dir" "$launcher_file"
}

# Opt-in: register the just-created worktree + AI session as a Termic task.
# Best-effort - any failure (termic not installed, session not yet
# registered, etc.) is a warning, not an error. The tmux session above is
# already usable regardless of whether this succeeds.
_register_termic () {
    [ -n "$termic_action" ] || return 0
    case "$termic_action" in
        new-task) _do_termic_new_task "$worktree_dir" "$agent_type" ;;
    esac
}

_finish () {
    _info "Done. Attach with: tmux attach -t $session"
    _info "(Whether your terminal/IDE app auto-discovers this tmux session is unverified - attach manually if not. See README.md.)"
}

cmd_start () {
    # Repo-dependent state is resolved here rather than at startup, so
    # `list` and `aws-preauth` work outside a git repo and never pay for
    # git/network work they don't use (notably _detect_main_branch's
    # ls-remote fallback).
    _ensure_git_repo
    MAIN_BRANCH="$(_detect_main_branch "$ROOTDIR")"
    [ -n "$worktree_root" ] || worktree_root="$HOME/.local/ai-task/worktrees/$REPO_NAME"

    _pick_first_ticket
    _validate_start_inputs
    _fetch_issue "$ticket_id"
    _compute_paths
    _report_plan

    if [ "$dry_run" = "1" ] ; then
        _info "(dry run) Would create worktree, mark issue in progress, and start tmux session."
        return 0
    fi

    _preflight_conflicts
    _create_worktree
    _setup_aws_readonly
    _write_sandbox_config
    _build_base_prompt
    _append_aws_prompt
    _append_extra_prompt
    _write_prompt_file
    _write_launcher
    # Mark in-progress only after everything that can fail pre-launch has
    # succeeded, and immediately before tmux comes up - the narrowest
    # window in which a ticket can be left "In Progress" with no session
    # behind it.
    _mark_in_progress
    _launch_tmux
    _register_termic
    _finish
}

# ── Shared option / config plumbing ──────────────────────────────────────────

# Consumes the remaining args (after the subcommand) into cli_* globals.
# Also sets: dry_run, first, ticket_id.
_parse_options () {
    cli_team="" cli_label="" cli_assignee="" cli_no_assignee="" cli_state="" cli_cycle="" cli_sort=""
    cli_priority="" cli_worktree_root="" cli_in_progress_state="" cli_blocked_state=""
    cli_agent_type="" cli_permission_mode="" cli_model="" cli_agent_settings="" cli_aws_readonly="" cli_allowed_hosts="" cli_termic="" cli_prompt_file=""
    cli_prompt_extra="" cli_creds_loader="" dry_run=0 first=0
    # Ticket id (for `start`) is collected as a bare positional argument
    # here, so --first can be recognized no matter where it appears
    # relative to it.
    ticket_id=""

    while [ $# -gt 0 ] ; do
        case "$1" in
            --team)                shift; _require_value --team "$#"; cli_team="$1" ;;
            --label)               shift; _require_value --label "$#"; cli_label="$1" ;;
            --assignee)            shift; _require_value --assignee "$#"; cli_assignee="$1" ;;
            --no-assignee)         cli_no_assignee="true" ;;
            --state)               shift; _require_value --state "$#"; cli_state="$1" ;;
            --cycle)               shift; _require_value --cycle "$#"; cli_cycle="$1" ;;
            --sort)                shift; _require_value --sort "$#"; cli_sort="$1" ;;
            --priority)            shift; _require_value --priority "$#"; cli_priority="$1" ;;
            --worktree-root)       shift; _require_value --worktree-root "$#"; cli_worktree_root="$1" ;;
            --in-progress-state)   shift; _require_value --in-progress-state "$#"; cli_in_progress_state="$1" ;;
            --blocked-state)       shift; _require_value --blocked-state "$#"; cli_blocked_state="$1" ;;
            --agent-type)          shift; _require_value --agent-type "$#"; cli_agent_type="$1" ;;
            --permission-mode)     shift; _require_value --permission-mode "$#"; cli_permission_mode="$1" ;;
            --model)               shift; _require_value --model "$#"; cli_model="$1" ;;
            --agent-settings)      shift; _require_value --agent-settings "$#"; cli_agent_settings="$1" ;;
            --creds-loader)        shift; _require_value --creds-loader "$#"; cli_creds_loader="$1" ;;
            --aws-readonly-role)   shift; _require_value --aws-readonly-role "$#"; cli_aws_readonly="$1" ;;
            --no-aws-readonly-role) cli_aws_readonly="__OFF__" ;;
            --allowed-hosts)       shift; _require_value --allowed-hosts "$#"; cli_allowed_hosts="$1" ;;
            --termic)              shift; _require_value --termic "$#"; cli_termic="$1" ;;
            --prompt-file)         shift; _require_value --prompt-file "$#"; cli_prompt_file="$1" ;;
            --prompt-extra)        shift; _require_value --prompt-extra "$#"; cli_prompt_extra="$1" ;;
            --first)               first=1 ;;
            -n|--dry-run)          dry_run=1 ;;
            -h|--help)             _usage; exit 0 ;;
            -*)                    _err "Unknown argument: $1"; _usage_error ;;
            *)
                # Bare positional - only meaningful as a ticket id for `start`.
                [ "$cmd" = "start" ] || { _err "Unexpected argument: $1 ('$cmd' doesn't take a ticket id)"; _usage_error; }
                [ -z "$ticket_id" ] || { _err "Multiple ticket ids given: '$ticket_id' and '$1'"; _usage_error; }
                ticket_id="$1"
                ;;
        esac
        shift
    done
}

# Resolves every option from cli flag > orig env snapshot > (post-config)
# env var > fallback env vars > default into the plain-named globals.
_resolve_options () {
    team="$(_resolve AITASK_TEAM "$cli_team" "" LINEAR_TEAM_ID)"
    label="$(_resolve AITASK_LABEL "$cli_label" "aitask")"
    assignee="$(_resolve AITASK_ASSIGNEE "$cli_assignee" "self")"
    no_assignee="$(_resolve AITASK_NO_ASSIGNEE "$cli_no_assignee" "false")"
    state="$(_resolve AITASK_STATE "$cli_state" "unstarted")"
    cycle="$(_resolve AITASK_CYCLE "$cli_cycle" "active")"
    sort="$(_resolve AITASK_SORT "$cli_sort" "priority" LINEAR_ISSUE_SORT)"
    priority="$(_resolve AITASK_PRIORITY "$cli_priority" "")"
    # Default is filled in by cmd_start once REPO_NAME is known - resolving
    # it here would force git-repo detection (and its network touch) onto
    # commands that never create a worktree.
    worktree_root="$(_resolve AITASK_WORKTREE_ROOT "$cli_worktree_root" "")"
    in_progress_state="$(_resolve AITASK_IN_PROGRESS_STATE "$cli_in_progress_state" "In Progress")"
    blocked_state="$(_resolve AITASK_BLOCKED_STATE "$cli_blocked_state" "Blocked")"
    agent_type="$(_resolve AITASK_AGENT_TYPE "$cli_agent_type" "claude")"
    permission_mode="$(_resolve AITASK_PERMISSION_MODE "$cli_permission_mode" "auto")"
    model="$(_resolve AITASK_MODEL "$cli_model" "")"
    agent_settings="$(_resolve AITASK_AGENT_SETTINGS "$cli_agent_settings" "")"
    creds_loader="$(_resolve AITASK_CREDS_LOADER "$cli_creds_loader" "")"
    aws_role_readonly="$(_resolve AITASK_AWS_ROLE_READONLY "$cli_aws_readonly" "")"
    # __OFF__ is the --no-aws-readonly-role sentinel: an explicit CLI "off" must win
    # over env/config, but _resolve treats empty as "unset" so it can't express
    # that directly. Empty (the default) means the feature is off.
    [ "$aws_role_readonly" != "__OFF__" ] || aws_role_readonly=""
    allowed_hosts_extra="$(_resolve AITASK_ALLOWED_HOSTS "$cli_allowed_hosts" "")"
    termic_action="$(_resolve AITASK_TERMIC "$cli_termic" "")"
    prompt_file="$(_resolve AITASK_PROMPT_FILE "$cli_prompt_file" "")"
    prompt_extra="$(_resolve AITASK_PROMPT_EXTRA "$cli_prompt_extra" "")"
}

_validate_options () {
    case "$agent_type" in
        claude|opencode) ;;
        *) _die "Invalid --agent-type '$agent_type' - must be 'claude' or 'opencode'" ;;
    esac

    # Validate --termic early so a typo in a config file fails fast. Empty
    # (the default) means the feature is off - no further checks needed.
    if [ -n "$termic_action" ] ; then
        case "$termic_action" in
            new-task) ;;
            *) _die "Invalid --termic '$termic_action' - currently the only supported action is 'new-task'" ;;
        esac
    fi

    if [ "$cmd" = "start" ] ; then
        _require_cmd "$agent_type" "selected via --agent-type"
    fi
}

# Sets globals: assignee_args, assignee_desc.
#
# --no-assignee wins over --assignee (any value, including "any") since
# it's a strictly narrower ask ("only unassigned"). linear-cli has three
# distinct, mutually-exclusive assignee modes at the CLI level - a plain
# --assignee filter, --all-assignees (our "any"), and --unassigned (our
# --no-assignee) - so we pick exactly one set of query args here rather
# than always passing --assignee.
_build_assignee_filter () {
    assignee_args=(--assignee "$assignee")
    assignee_desc="assignee=$assignee"
    if [ "$no_assignee" = "true" ] ; then
        assignee_args=(--unassigned)
        assignee_desc="assignee=none"
    elif [ "$assignee" = "any" ] ; then
        assignee_args=(--all-assignees)
        assignee_desc="assignee=any"
    fi
}

# Prompts for (and persists) AITASK_TEAM when it's needed for a Linear query
# and still unresolved. Sets global: team.
_ensure_team_configured () {
    # Team is only needed for a Linear query - `start TICKET-ID` (without
    # --first) never queries at all, so it shouldn't be prompted for one.
    local need_team=0
    [ "$cmd" != "list" ] || need_team=1
    [ "$cmd" != "start" ] || [ "$first" != "1" ] || need_team=1
    [ "$need_team" = "1" ] || return 0
    [ -z "$team" ] || return 0

    # --team has no hardcoded default on purpose (was a source of surprises
    # when this script only ever ran against one team). Prompt once,
    # interactively, and persist the answer so future runs don't ask again.
    if [ ! -t 0 ] ; then
        _die "No Linear team configured (--team / AITASK_TEAM / LINEAR_TEAM_ID / config file), and not running interactively to prompt for one."
    fi
    printf "No Linear team configured. Enter your Linear team key (e.g. DVOPS): " 1>&2
    read -r team || _die "No team entered."
    [ -n "$team" ] || _die "No team entered."
    # Append to whichever config file already exists, closest scope
    # first; if none exist yet, create a fresh one at the simplest
    # default location.
    local target_conf c
    target_conf=""
    for c in "$(pwd)/.ai-taskrc" "$(pwd)/ai-task.conf" "$HOME/.ai-taskrc" "$HOME/.config/ai-task/ai-task.conf" ; do
        [ ! -e "$c" ] || { target_conf="$c"; break; }
    done
    [ -n "$target_conf" ] || target_conf="$HOME/.ai-taskrc"
    mkdir -p "$(dirname "$target_conf")"
    printf '\nAITASK_TEAM=%q\n' "$team" >> "$target_conf"
    _info "Saved AITASK_TEAM=$team to $target_conf"
}

# Sets globals: ROOTDIR, REPO_NAME.
_ensure_git_repo () {
    ROOTDIR="$(git rev-parse --show-toplevel 2>/dev/null)" || {
        _err "Not inside a git repository. cd into the repo you want to automate and try again."
        _usage_error
    }
    # Derived from the remote (not the local worktree dir name), so the default
    # worktree path is stable regardless of which worktree this is run from.
    REPO_NAME="$(basename -s .git "$(git -C "$ROOTDIR" remote get-url origin)")" \
        || _die "Couldn't read the 'origin' remote of $ROOTDIR - can't derive the repo name."
}

main () {
    local cmd=""
    if [ $# -gt 0 ] ; then
        case "$1" in
            -h|--help) _usage; exit 0 ;;
            -*) : ;;   # leave cmd empty - falls through to "no command" below
            *)  cmd="$1"; shift ;;
        esac
    fi

    # ── Subcommand dispatch (aws-preauth exits early - no Linear, no git) ──
    case "$cmd" in
        list|start) ;;
        aws-preauth)
            [ $# -eq 2 ] || _die "Usage: $SCRIPT aws-preauth <output-dir> <aws-role-name>"
            _cmd_aws_preauth "$1" "$2"
            exit 0
            ;;
        "")
            _err "No command given."
            _usage_error
            ;;
        *)
            _err "Unknown command: $cmd"
            _usage_error
            ;;
    esac

    # Parse options before the Linear checks, so argument errors (unknown
    # flag, missing value) are reported instantly without a network auth
    # round-trip. cmd/first/dry_run/ticket_id are globals set here.
    _parse_options "$@"

    # list/start both need the linear CLI and a working auth session - a
    # setup problem is diagnosed clearly here instead of surfacing as a
    # confusing failure partway through a query later.
    _require_cmd linear "Install it with: brew install schpet/tap/linear"
    _require_cmd jq
    linear auth whoami >/dev/null 2>&1 \
        || _die "linear CLI is not set up (couldn't authenticate). Run 'linear auth login' - see README.md 'Setting up linear'."

    # Option / env / config resolution (see precedence note above the
    # _snapshot_env definition).
    _snapshot_env
    # Config file name can be either `ai-task.conf` or `.ai-taskrc` (rc-file
    # style), checked at both the home and project-local scope. Later files
    # win if more than one exists.
    _loadconf "$HOME/.config/ai-task/ai-task.conf"
    _loadconf "$HOME/.ai-taskrc"
    _loadconf "$(pwd)/ai-task.conf"
    _loadconf "$(pwd)/.ai-taskrc"

    _resolve_options
    _validate_options
    _build_assignee_filter
    _ensure_team_configured

    if [ "$cmd" = "list" ] ; then
        cmd_list
    else
        cmd_start
    fi
}

main "$@"
