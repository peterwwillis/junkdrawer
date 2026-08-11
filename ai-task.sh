#!/usr/bin/env bash
# ai-task.sh - list Linear issues ready for an AI to work on, and start one
#
# See README.md in this directory for full design notes and gotchas. Quick
# summary: `list` shows ready-to-work Linear issues matching your filters;
# `start <TICKET-ID>` creates an isolated git worktree for a specific one,
# pre-authenticates read-only AWS credentials by default (AWS ReadOnly
# mode - --aws-readonly / --no-aws-readonly / `aws-preauth` command), and
# launches an autonomous AI session in tmux - `claude` (default) or
# `opencode` (--agent-type opencode).
#
# Requires: the `linear` CLI (authenticated), jq. `start` additionally
# requires git, tmux, and the CLI for whichever --agent-type is selected
# (claude or opencode). `aws-preauth` additionally requires aws-sso.
set -eu
[ "${DEBUG:-0}" = "1" ] && set -x

SCRIPT="$(basename "$0")"
REPO_NAME="<repo>"   # placeholder; replaced once we confirm we're in a git repo

_err()  { printf "%s: Error: %s\n" "$SCRIPT" "$*" 1>&2 ; }
_info() { printf "%s: Info: %s\n" "$SCRIPT" "$*" 1>&2 ; }
_die()  { _err "$@"; exit 1; }

# _cmd_aws_preauth OUTDIR
#
# Mints short-lived STS credentials for the ':ReadOnly-NoSecrets' role in
# every AWS account you have access to (via aws-sso), and writes them as an
# isolated, plain-static-credential AWS config/credentials file pair under
# OUTDIR. These files never reference aws-sso or credential_process - they're
# just static keys, so a sandboxed session using them has no path to
# escalate to a different role even if it tries.
#
# Credentials expire in about an hour. That's an AWS platform limit for
# this credential type (SSO-federated / role-chained session credentials
# are always capped at 1hr, regardless of the permission set's configured
# Session Duration) - not something this script, aws-sso, or any client can
# configure around. Just re-run `ai-task.sh aws-preauth OUTDIR` to refresh.
#
# `ai-task.sh start` calls this for you at worktree-creation time whenever
# AWS ReadOnly mode is on (the default - see --no-aws-readonly). Run it
# directly to refresh an existing worktree's expired credentials
# without recreating the task. Never run it from inside an ai-task session
# itself - it's the trusted side of the boundary, and needs your own valid
# `aws-sso login` session to work.
_cmd_aws_preauth() {
    local outdir="$1" credfile conffile readme region profiles count profile
    local creds_json access_key secret_key session_token expiration

    command -v aws-sso >/dev/null 2>&1 || _die "aws-sso not found in PATH"
    command -v jq >/dev/null 2>&1 || _die "jq not found in PATH"

    mkdir -p "$outdir"
    credfile="$outdir/credentials"
    conffile="$outdir/config"
    readme="$outdir/README.md"
    : > "$credfile"
    : > "$conffile"
    chmod 600 "$credfile" "$conffile"

    region="$(awk '/DefaultRegion/{print $2}' ~/.config/aws-sso/config.yaml 2>/dev/null)"
    region="${region:-us-east-1}"

    profiles="$(aws configure list-profiles | grep ':ReadOnly-NoSecrets$' || true)"
    if [ -z "$profiles" ] ; then
        _err "No ':ReadOnly-NoSecrets' profiles found."
        _die "Try: aws-sso login && aws-sso setup profiles --force"
    fi

    {
        printf '# Read-only AWS access for this ai-task session\n\n'
        printf 'This session has READ-ONLY AWS access only, scoped per account via the\n'
        printf 'profiles below. There is no admin/write path available here: aws-sso is\n'
        printf 'not usable in this sandbox (its config/cache is blocked), and these\n'
        printf 'profile files contain only short-lived static credentials - no\n'
        printf '`credential_process`, no reference to aws-sso at all.\n\n'
        printf 'Credentials expire in about an hour (an AWS platform limit for this\n'
        printf 'credential type, not something configurable - see README.md). Re-run\n'
        printf '`ai-task.sh aws-preauth %s` to refresh.\n\n' "$outdir"
        printf 'Before running AWS or terraform commands in a given\n'
        printf '`env/aws/<tenant>/...` directory, set the matching profile first, e.g.:\n\n'
        printf '    export AWS_PROFILE="<tenant>:ReadOnly-NoSecrets"\n\n'
        printf 'Available profiles:\n'
    } > "$readme"

    count=0
    while IFS= read -r profile ; do
        [ -n "$profile" ] || continue
        _info "Minting short-lived credentials for '$profile'..."
        creds_json="$(aws-sso process -p "$profile" 2>&1)" || {
            _err "Failed to get credentials for '$profile'."
            _err "Is your aws-sso session valid? Try: aws-sso login"
            _die "$creds_json"
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

    {
        printf '\n`make tfsh-apply` / `terraform apply` will fail with an AWS permission\n'
        printf 'error in this environment by design - this session can only plan and\n'
        printf 'investigate, not apply. If a task needs an actual apply, describe what\n'
        printf 'needs to change (e.g. in the PR description) - a human applies it via\n'
        printf 'the existing `/terraform-apply` PR-comment workflow.\n'
    } >> "$readme"

    _info "Wrote $count read-only profile(s) to $outdir"
}

_usage() {
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
  aws-preauth OUTDIR      Mint read-only AWS credentials into OUTDIR. Used
                         internally by AWS ReadOnly mode (on by default -
                         see --no-aws-readonly); run it directly to
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
  --aws-readonly               AWS ReadOnly mode: pre-auth read-only AWS
                              credentials + AWS-specific prompt/sandbox
                              additions (default: on)
  --no-aws-readonly           Force AWS ReadOnly mode off, overriding
                              config - use this for a repo with no
                              cloud/AWS component
  --allowed-hosts HOSTS       Comma-separated extra sandbox network
                              allowlist entries
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
AITASK_AWS_READONLY, AITASK_ALLOWED_HOSTS,
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
    exit 1
}

# ── Require a git repo ──────────────────────────────────────────────────────
# Needed to create worktrees and to find a project-local config file.
if ! ROOTDIR="$(git rev-parse --show-toplevel 2>/dev/null)" ; then
    _err "Not inside a git repository. cd into the repo you want to automate and try again."
    _usage
fi
# Derived from the remote (not the local worktree dir name), so the default
# worktree path is stable regardless of which worktree this is run from.
REPO_NAME="$(basename -s .git "$(git -C "$ROOTDIR" remote get-url origin)")"

# ── Subcommand dispatch ─────────────────────────────────────────────────────
cmd=""
if [ $# -gt 0 ] ; then
    case "$1" in
        -h|--help) _usage ;;
        -*) : ;;   # leave cmd empty - falls through to "no command" below
        *)  cmd="$1"; shift ;;
    esac
fi

case "$cmd" in
    list|start) ;;
    aws-preauth)
        [ $# -eq 1 ] || _die "Usage: $SCRIPT aws-preauth <output-dir>"
        _cmd_aws_preauth "$1"
        exit 0
        ;;
    "")
        _err "No command given."
        _usage
        ;;
    *)
        _err "Unknown command: $cmd"
        _usage
        ;;
esac

command -v linear >/dev/null 2>&1 || _die "Required command 'linear' not found in PATH. Install it with: brew install schpet/tap/linear"
command -v jq >/dev/null 2>&1 || _die "Required command 'jq' not found in PATH"

# Quick, lightweight check that linear-cli is actually authenticated, so a
# setup problem is diagnosed clearly here instead of surfacing as a
# confusing failure partway through a query later.
linear auth whoami >/dev/null 2>&1 || _die "linear CLI is not set up (couldn't authenticate). Run 'linear auth login' - see README.md 'Setting up linear'."

if [ "$cmd" = "start" ] ; then
    for tool in git tmux ; do
        command -v "$tool" >/dev/null 2>&1 || _die "Required command '$tool' not found in PATH"
    done
fi
# The agent CLI itself (claude or opencode) is checked further down, once
# --agent-type is resolved.
# Ticket id (for `start`) is collected as a bare positional argument by
# the option-parsing loop below, so --first can be recognized no matter
# where it appears relative to it.
ticket_id=""

# ── Option / env / config resolution ────────────────────────────────────────
#
# Precedence (highest wins): --flag > env var you set for this invocation >
# config file > linear-cli's own env vars (team/sort only) > hardcoded
# default. We snapshot the "real" env vars below BEFORE sourcing config
# files, so a persisted config can't clobber something you explicitly
# exported just for this run.
_AITASK_VARS="AITASK_TEAM AITASK_LABEL AITASK_ASSIGNEE AITASK_NO_ASSIGNEE AITASK_STATE AITASK_CYCLE
AITASK_SORT AITASK_PRIORITY AITASK_WORKTREE_ROOT AITASK_IN_PROGRESS_STATE
AITASK_BLOCKED_STATE AITASK_AGENT_TYPE AITASK_PERMISSION_MODE AITASK_MODEL AITASK_AGENT_SETTINGS
AITASK_AWS_READONLY AITASK_ALLOWED_HOSTS
AITASK_PROMPT_FILE AITASK_PROMPT_EXTRA"
for v in $_AITASK_VARS ; do
    eval "orig_$v=\"\${$v:-}\""
done

# Config file name can be either `ai-task.conf` or `.ai-taskrc` (rc-file
# style), checked at both the home and project-local scope. Later files
# win if more than one exists.
_loadconf() { [ ! -e "$1" ] || . "$1" ; }
_loadconf "$HOME/.config/ai-task/ai-task.conf"
_loadconf "$HOME/.ai-taskrc"
_loadconf "$(pwd)/ai-task.conf"
_loadconf "$(pwd)/.ai-taskrc"

# _resolve VAR CLIVAL DEFAULT [FALLBACK_ENV_VAR ...]
_resolve() {
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
_query_ready_issues() {
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

cli_team="" cli_label="" cli_assignee="" cli_no_assignee="" cli_state="" cli_cycle="" cli_sort=""
cli_priority="" cli_worktree_root="" cli_in_progress_state="" cli_blocked_state=""
cli_agent_type="" cli_permission_mode="" cli_model="" cli_agent_settings="" cli_aws_readonly="" cli_allowed_hosts="" cli_prompt_file=""
cli_prompt_extra="" dry_run=0 first=0

while [ $# -gt 0 ] ; do
    case "$1" in
        --team)               shift; cli_team="$1" ;;
        --label)               shift; cli_label="$1" ;;
        --assignee)            shift; cli_assignee="$1" ;;
        --no-assignee)         cli_no_assignee="true" ;;
        --state)               shift; cli_state="$1" ;;
        --cycle)               shift; cli_cycle="$1" ;;
        --sort)                shift; cli_sort="$1" ;;
        --priority)            shift; cli_priority="$1" ;;
        --worktree-root)        shift; cli_worktree_root="$1" ;;
        --in-progress-state)    shift; cli_in_progress_state="$1" ;;
        --blocked-state)       shift; cli_blocked_state="$1" ;;
        --agent-type)           shift; cli_agent_type="$1" ;;
        --permission-mode)      shift; cli_permission_mode="$1" ;;
        --model)               shift; cli_model="$1" ;;
        --agent-settings)      shift; cli_agent_settings="$1" ;;
        --aws-readonly)         cli_aws_readonly="true" ;;
        --no-aws-readonly)      cli_aws_readonly="false" ;;
        --allowed-hosts)        shift; cli_allowed_hosts="$1" ;;
        --prompt-file)          shift; cli_prompt_file="$1" ;;
        --prompt-extra)        shift; cli_prompt_extra="$1" ;;
        --first)               first=1 ;;
        -n|--dry-run)          dry_run=1 ;;
        -h|--help)             _usage ;;
        -*)                    _err "Unknown argument: $1"; _usage ;;
        *)
            # Bare positional - only meaningful as a ticket id for `start`.
            [ "$cmd" = "start" ] || { _err "Unexpected argument: $1 ('$cmd' doesn't take a ticket id)"; _usage; }
            [ -z "$ticket_id" ] || { _err "Multiple ticket ids given: '$ticket_id' and '$1'"; _usage; }
            ticket_id="$1"
            ;;
    esac
    shift
done

team="$(_resolve AITASK_TEAM "$cli_team" "" LINEAR_TEAM_ID)"
label="$(_resolve AITASK_LABEL "$cli_label" "aitask")"
assignee="$(_resolve AITASK_ASSIGNEE "$cli_assignee" "self")"
no_assignee="$(_resolve AITASK_NO_ASSIGNEE "$cli_no_assignee" "false")"
state="$(_resolve AITASK_STATE "$cli_state" "unstarted")"
cycle="$(_resolve AITASK_CYCLE "$cli_cycle" "active")"
sort="$(_resolve AITASK_SORT "$cli_sort" "priority" LINEAR_ISSUE_SORT)"
priority="$(_resolve AITASK_PRIORITY "$cli_priority" "")"
worktree_root="$(_resolve AITASK_WORKTREE_ROOT "$cli_worktree_root" "$HOME/.local/ai-task/worktrees/$REPO_NAME")"
in_progress_state="$(_resolve AITASK_IN_PROGRESS_STATE "$cli_in_progress_state" "In Progress")"
blocked_state="$(_resolve AITASK_BLOCKED_STATE "$cli_blocked_state" "Blocked")"
agent_type="$(_resolve AITASK_AGENT_TYPE "$cli_agent_type" "claude")"
permission_mode="$(_resolve AITASK_PERMISSION_MODE "$cli_permission_mode" "auto")"
model="$(_resolve AITASK_MODEL "$cli_model" "")"
agent_settings="$(_resolve AITASK_AGENT_SETTINGS "$cli_agent_settings" "")"
aws_readonly="$(_resolve AITASK_AWS_READONLY "$cli_aws_readonly" "true")"
allowed_hosts_extra="$(_resolve AITASK_ALLOWED_HOSTS "$cli_allowed_hosts" "")"
prompt_file="$(_resolve AITASK_PROMPT_FILE "$cli_prompt_file" "")"
prompt_extra="$(_resolve AITASK_PROMPT_EXTRA "$cli_prompt_extra" "")"

case "$agent_type" in
    claude|opencode) ;;
    *) _die "Invalid --agent-type '$agent_type' - must be 'claude' or 'opencode'" ;;
esac
if [ "$cmd" = "start" ] ; then
    command -v "$agent_type" >/dev/null 2>&1 || _die "Required command '$agent_type' not found in PATH (selected via --agent-type)"
fi

# --no-assignee wins over --assignee (any value, including "any") since
# it's a strictly narrower ask ("only unassigned"). linear-cli has three
# distinct, mutually-exclusive assignee modes at the CLI level - a plain
# --assignee filter, --all-assignees (our "any"), and --unassigned (our
# --no-assignee) - so we pick exactly one set of query args here rather
# than always passing --assignee.
assignee_args=(--assignee "$assignee")
assignee_desc="assignee=$assignee"
if [ "$no_assignee" = "true" ] ; then
    assignee_args=(--unassigned)
    assignee_desc="assignee=none"
elif [ "$assignee" = "any" ] ; then
    assignee_args=(--all-assignees)
    assignee_desc="assignee=any"
fi

# Team is only needed for a Linear query - `start TICKET-ID` (without
# --first) never queries at all, so it shouldn't be prompted for one.
need_team=0
[ "$cmd" != "list" ] || need_team=1
[ "$cmd" != "start" ] || [ "$first" != "1" ] || need_team=1

# --team has no hardcoded default on purpose (was a source of surprises
# when this script only ever ran against one team). Prompt once,
# interactively, and persist the answer so future runs don't ask again.
# Only needed if we're actually about to run a Linear query (`list`, or
# `start --first`) - plain `start TICKET-ID` never queries at all.
if [ "$need_team" = "1" ] && [ -z "$team" ] ; then
    [ -t 0 ] || _die "No Linear team configured (--team / AITASK_TEAM / LINEAR_TEAM_ID / config file), and not running interactively to prompt for one."
    printf "No Linear team configured. Enter your Linear team key (e.g. DVOPS): " 1>&2
    read -r team
    [ -n "$team" ] || _die "No team entered."
    # Append to whichever config file already exists, closest scope
    # first; if none exist yet, create a fresh one at the simplest
    # default location.
    target_conf=""
    for c in "$(pwd)/.ai-taskrc" "$(pwd)/ai-task.conf" "$HOME/.ai-taskrc" "$HOME/.config/ai-task/ai-task.conf" ; do
        [ ! -e "$c" ] || { target_conf="$c"; break; }
    done
    [ -n "$target_conf" ] || target_conf="$HOME/.ai-taskrc"
    mkdir -p "$(dirname "$target_conf")"
    printf '\nAITASK_TEAM=%q\n' "$team" >> "$target_conf"
    _info "Saved AITASK_TEAM=$team to $target_conf"
fi

# ── list command ─────────────────────────────────────────────────────────────

if [ "$cmd" = "list" ] ; then
    _info "Querying Linear: team=$team label=$label state=$state cycle=$cycle $assignee_desc sort=$sort${priority:+ priority=$priority}"
    matches_json="$(_query_ready_issues)"

    count="$(printf '%s' "$matches_json" | jq 'length')"
    if [ "$count" -eq 0 ] ; then
        _info "No ready issues found for team $team (checked state=$state, cycle=$cycle, label=$label, $assignee_desc${priority:+, priority=$priority}, unblocked)."
        exit 0
    fi
    printf '%s' "$matches_json" | jq -r '.[] | "\(.identifier)\t\(.title)"'
    exit 0
fi

# ── start command ────────────────────────────────────────────────────────────

if [ "$first" = "1" ] ; then
    [ -z "$ticket_id" ] || _die "Can't pass both a ticket id ('$ticket_id') and --first."
    _info "Querying Linear for the top match: team=$team label=$label state=$state cycle=$cycle $assignee_desc sort=$sort${priority:+ priority=$priority}"
    matches_json="$(_query_ready_issues)"
    ticket_id="$(printf '%s' "$matches_json" | jq -r 'first | .identifier // empty')"
    [ -n "$ticket_id" ] || _die "No ready issues found matching filters - nothing to start with --first."
else
    [ -n "$ticket_id" ] || _die "Usage: $SCRIPT start <TICKET-ID> [OPTIONS] (or pass --first to pick the top match automatically)"
fi

[ -z "$agent_settings" ] || [ -r "$agent_settings" ] || _die "--agent-settings '$agent_settings' not found or not readable"
[ -z "$agent_settings" ] || jq empty "$agent_settings" 2>/dev/null || _die "--agent-settings '$agent_settings' is not valid JSON"

issue_json="$(linear issue view "$ticket_id" --json)" || _die "Could not fetch issue '$ticket_id' from Linear."
identifier="$(printf '%s' "$issue_json" | jq -r '.identifier')"
title="$(printf '%s' "$issue_json" | jq -r '.title')"
url="$(printf '%s' "$issue_json" | jq -r '.url')"
description="$(printf '%s' "$issue_json" | jq -r '.description // ""')"
branch="$(printf '%s' "$issue_json" | jq -r '.branchName')"

lower_id="$(printf '%s' "$identifier" | tr '[:upper:]' '[:lower:]')"
worktree_dir="$worktree_root/$lower_id"
session="aitask-$lower_id"

_info "Starting $identifier: $title"
_info "  $url"
_info "Branch:    $branch"
_info "Worktree:  $worktree_dir"
_info "Session:   $session"
_info "Agent:     $agent_type"
_info "Model:     ${model:-<agent default>}"
_info "AWS ReadOnly mode: $aws_readonly"

if [ "$dry_run" = "1" ] ; then
    _info "(dry run) Would create worktree, mark issue in progress, and start tmux session."
    exit 0
fi

if [ -e "$worktree_dir" ] ; then
    _die "Worktree directory already exists: $worktree_dir"
fi

if tmux has-session -t "$session" 2>/dev/null ; then
    _die "tmux session '$session' already exists. Attach with: tmux attach -t $session"
fi

# ── Create the worktree ─────────────────────────────────────────────────────

_info "Fetching latest origin/main..."
git -C "$ROOTDIR" fetch origin main

_info "Creating worktree..."
mkdir -p "$worktree_root"
git -C "$ROOTDIR" worktree add -b "$branch" "$worktree_dir" origin/main

# ── AWS ReadOnly mode: read-only AWS credentials ────────────────────────────

aws_dir="$worktree_dir/.aitask-aws"
if [ "$aws_readonly" = "true" ] ; then
    _info "Minting read-only AWS credentials for the sandboxed session..."
    _cmd_aws_preauth "$aws_dir"
fi

# ── Sandbox config ───────────────────────────────────────────────────────────
# hosts/cred_files are shared between both agent backends - only the JSON
# shape each one wants differs (see README.md "Safety" for what each
# backend's isolation mechanism actually is and its known gaps).

hosts=(github.com api.github.com raw.githubusercontent.com linear.app api.linear.app)
[ "$aws_readonly" != "true" ] || hosts+=("*.amazonaws.com" "169.254.169.254" "169.254.170.2")
if [ -n "$allowed_hosts_extra" ] ; then
    IFS=',' read -r -a extra_hosts <<< "$allowed_hosts_extra"
    hosts+=("${extra_hosts[@]}")
fi
hosts_json="$(printf '%s\n' "${hosts[@]}" | jq -R . | jq -s .)"

cred_files=("~/.ssh")
[ "$aws_readonly" != "true" ] || cred_files+=("~/.config/aws-sso" "~/.aws")

if [ "$agent_type" = "claude" ] ; then
    _info "Writing sandbox config for the worktree (.claude/settings.local.json)..."
    mkdir -p "$worktree_dir/.claude"
    cred_files_json="$(printf '%s\n' "${cred_files[@]}" | jq -R '{path: ., mode: "deny"}' | jq -s .)"
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
else
    # opencode: no built-in equivalent to Claude Code's sandbox, so isolation
    # comes from the third-party `opencode-sandbox` plugin (wraps
    # @anthropic-ai/sandbox-runtime - the same seatbelt/bubblewrap primitive
    # Claude Code itself uses). It fails OPEN if it can't initialize - see
    # README.md "Safety" for that caveat and what is/isn't covered.
    _info "Writing opencode sandbox config for the worktree..."
    deny_read_json="$(printf '%s\n' "${cred_files[@]}" | jq -R . | jq -s .)"
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
    # validated as valid JSON above) and write the merged result to our own
    # generated file, pointed at via OPENCODE_CONFIG - which loads *alongside*
    # (not instead of) the project's own opencode.json.
    opencode_config_file="$worktree_dir/.aitask-opencode-config.json"
    base_config="{}"
    [ -z "$agent_settings" ] || base_config="$(cat "$agent_settings")"
    printf '%s' "$base_config" | jq '.plugin = ((.plugin // []) + ["opencode-sandbox"] | unique)' > "$opencode_config_file"
fi

_info "Marking $identifier as '$in_progress_state' in Linear..."
linear issue update "$identifier" --state "$in_progress_state"

# ── Prompt ───────────────────────────────────────────────────────────────────
# Note: read -d '' (rather than prompt="$(cat <<EOP ... )") avoids a bash
# quirk where an apostrophe inside a heredoc nested in $(...) breaks parsing.

if [ -n "$prompt_file" ] ; then
    [ -r "$prompt_file" ] || _die "--prompt-file '$prompt_file' not found or not readable"
    prompt="$(cat "$prompt_file")"
    # Plain string substitution only - the file is never sourced/eval'd.
    prompt="${prompt//\{\{IDENTIFIER\}\}/$identifier}"
    prompt="${prompt//\{\{TITLE\}\}/$title}"
    prompt="${prompt//\{\{URL\}\}/$url}"
    prompt="${prompt//\{\{DESCRIPTION\}\}/$description}"
    prompt="${prompt//\{\{BLOCKED_STATE\}\}/$blocked_state}"
else
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

if [ "$aws_readonly" = "true" ] ; then
    prompt="$prompt

AWS ReadOnly mode is on for this repo/session:
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
  user to run \`ai-task.sh aws-preauth\` on this worktree's .aitask-aws/
  directory to refresh your credentials, then continue once they confirm.
- Follow this repo's CLAUDE.md and .claude/rules/, especially the
  terraformsh/make wrapper workflow - never run terraform directly."
fi

if [ -n "$prompt_extra" ] ; then
    prompt="$prompt

Additional instructions:
$prompt_extra"
fi

prompt_file_out="$worktree_dir/.aitask-prompt.txt"
printf '%s' "$prompt" > "$prompt_file_out"

launcher_file="$worktree_dir/.aitask-launch.sh"
{
    printf '#!/usr/bin/env bash\n'
    printf 'cd %q\n' "$worktree_dir"
    if [ "$aws_readonly" = "true" ] ; then
        printf 'unset AWS_PROFILE\n'
        printf 'export AWS_CONFIG_FILE=%q\n' "$aws_dir/config"
        printf 'export AWS_SHARED_CREDENTIALS_FILE=%q\n' "$aws_dir/credentials"
    fi
    if [ "$agent_type" = "claude" ] ; then
        printf 'exec claude'
        printf ' --permission-mode %q' "$permission_mode"
        [ -z "$model" ] || printf ' --model %q' "$model"
        [ -z "$agent_settings" ] || printf ' --settings %q' "$agent_settings"
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
        printf ' "$(cat %q)"\n' "$prompt_file_out"
    fi
} > "$launcher_file"
chmod +x "$launcher_file"

_info "Starting tmux session '$session'..."
tmux new-session -d -s "$session" -c "$worktree_dir" "$launcher_file"

_info "Done. Attach with: tmux attach -t $session"
_info "(Whether your terminal/IDE app auto-discovers this tmux session is unverified - attach manually if not. See README.md.)"
