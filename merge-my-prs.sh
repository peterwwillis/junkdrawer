#!/usr/bin/env bash
#
# merge-my-prs.sh - pick some of your open PRs from a dialog menu, then merge
# them one at a time. Before each merge the PR branch is brought up to date
# with its base (the GitHub "Update branch" button, via `gh pr update-branch`)
# and its checks are awaited, because every merge makes the remaining PRs
# stale.
#
# Usage: bin/merge-my-prs.sh [options]
#   -a AUTHOR   list PRs authored by this GitHub user (default: @me, unless -A given)
#   -A ASSIGNEE list PRs assigned to this GitHub user (@me allowed); combine with
#               -a to require both
#   -m METHOD   squash | merge | rebase   (default: squash, this repo's norm)
#   -r          update branches by rebase instead of merge commit
#   -d          delete the head branch after each merge
#   -D          also list draft PRs (hidden by default; they can't be merged)
#   -S          also list stacked PRs whose base isn't the default branch
#               (hidden by default; their parent must merge first)
#   -n          dry run: choose PRs and show the plan, change nothing
#   -h          help
#
# Needs: gh (authenticated), jq, dialog, and a real terminal (TTY).
# Never uses --admin: branch protection / required checks are respected.

set -euo pipefail

AUTHOR=""
ASSIGNEE=""
METHOD="squash"
UPDATE_REBASE=0
DELETE_BRANCH=0
DRY_RUN=0
INCLUDE_DRAFTS=0
INCLUDE_STACKED=0

usage() { sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; }

while getopts "a:A:m:rdnDSh" opt; do
  case "$opt" in
    a) AUTHOR="$OPTARG" ;;
    A) ASSIGNEE="$OPTARG" ;;
    m) METHOD="$OPTARG" ;;
    r) UPDATE_REBASE=1 ;;
    d) DELETE_BRANCH=1 ;;
    n) DRY_RUN=1 ;;
    D) INCLUDE_DRAFTS=1 ;;
    S) INCLUDE_STACKED=1 ;;
    h) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

case "$METHOD" in squash | merge | rebase) ;; *)
  echo "invalid -m '$METHOD' (squash|merge|rebase)" >&2; exit 2 ;;
esac
[[ -z "$AUTHOR" && -z "$ASSIGNEE" ]] && AUTHOR="@me"
# Passed to gh as single argv elements, but still restrict them to valid logins.
for v in AUTHOR ASSIGNEE; do
  [[ -z "${!v}" || "${!v}" =~ ^(@me|[A-Za-z0-9][A-Za-z0-9-]{0,38})$ ]] || {
    echo "invalid $v '${!v}'" >&2; exit 2; }
done

for cmd in gh jq dialog; do
  command -v "$cmd" >/dev/null || { echo "missing dependency: $cmd" >&2; exit 1; }
done
[[ -t 0 && -t 1 ]] || { echo "needs an interactive terminal (dialog)" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

BASE_BRANCH="$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)"

# ---------------------------------------------------------------- list PRs
list_args=(--state open --limit 100
  --json number,title,headRefName,baseRefName,isDraft,author)
[[ -n "$AUTHOR" ]] && list_args+=(--author "$AUTHOR")
[[ -n "$ASSIGNEE" ]] && list_args+=(--assignee "$ASSIGNEE")
gh pr list "${list_args[@]}" >"$TMP/all.json"

# Hide un-mergeable PRs unless -D (drafts) / -S (stacked) was given.
hidden_drafts="$(jq '[.[] | select(.isDraft)] | length' "$TMP/all.json")"
hidden_stacked="$(jq --arg base "$BASE_BRANCH" \
  '[.[] | select(.baseRefName != $base)] | length' "$TMP/all.json")"
jq --arg base "$BASE_BRANCH" \
   --argjson d "$INCLUDE_DRAFTS" --argjson s "$INCLUDE_STACKED" \
  '[.[] | select(($d == 1 or (.isDraft | not))
                 and ($s == 1 or .baseRefName == $base))]' \
  "$TMP/all.json" >"$TMP/prs.json"

[[ "$INCLUDE_DRAFTS" -eq 1 ]] && hidden_drafts=0
[[ "$INCLUDE_STACKED" -eq 1 ]] && hidden_stacked=0
if [[ "$hidden_drafts" -gt 0 || "$hidden_stacked" -gt 0 ]]; then
  echo "Hidden: $hidden_drafts draft (-D to show), $hidden_stacked stacked on a non-$BASE_BRANCH base (-S to show); a PR can be both."
fi

count="$(jq length "$TMP/prs.json")"
if [[ "$count" -eq 0 ]]; then
  echo "No mergeable open PRs for author=${AUTHOR:--} assignee=${ASSIGNEE:--}."; exit 0
fi

# --------------------------------------------------------------- the menu
# dialog tag = PR number; item = title + markers. Drafts and stacked PRs
# (base != default branch) start unchecked.
items=()
while IFS=$'\t' read -r num title base draft; do
  marker=""
  [[ "$draft" == "true" ]] && marker=" [draft]"
  [[ "$base" != "$BASE_BRANCH" ]] && marker="$marker [base: $base]"
  state="on"
  [[ -n "$marker" ]] && state="off"
  items+=("$num" "${title}${marker}" "$state")
done < <(jq -r 'sort_by(.number)[] |
  [.number, .title, .baseRefName, .isDraft] | @tsv' "$TMP/prs.json")

dialog --clear --separate-output \
  --title "Merge PRs" \
  --checklist "SPACE toggles, ENTER confirms. PRs merge in ascending number order, one at a time." \
  0 0 0 "${items[@]}" 2>"$TMP/selected" || { clear; echo "Cancelled."; exit 0; }
clear

selected=()
while IFS= read -r n; do
  [[ "$n" =~ ^[0-9]+$ ]] && selected+=("$n")
done < <(sort -n "$TMP/selected")

if [[ ${#selected[@]} -eq 0 ]]; then
  echo "Nothing selected."; exit 0
fi

echo "Will merge (in order), method=$METHOD:"
for n in "${selected[@]}"; do
  jq -r --argjson n "$n" '.[] | select(.number==$n) | "  #\(.number)  [\(.author.login)] \(.title)"' "$TMP/prs.json"
done
if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "(dry run - nothing changed)"; exit 0
fi
read -r -p "Proceed? Merging is not easily reversible. [y/N] " ans
[[ "$ans" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

# ---------------------------------------------------------------- helpers
pr_field() { gh pr view "$1" --json "$2" -q ".$2"; }

# mergeStateStatus is computed lazily and reads UNKNOWN for a moment.
merge_state() {
  local s i
  for i in $(seq 1 15); do
    s="$(pr_field "$1" mergeStateStatus)"
    [[ "$s" != "UNKNOWN" ]] && { echo "$s"; return; }
    sleep 2
  done
  echo "UNKNOWN"
}

wait_for_new_head() { # $1=pr $2=old sha
  local i
  for i in $(seq 1 30); do
    [[ "$(pr_field "$1" headRefOid)" != "$2" ]] && return 0
    sleep 2
  done
  return 1
}

wait_for_checks() { # returns 0 pass, 1 fail/none
  local n="$1" attempt rc
  sleep 5 # give GitHub time to register the new check runs
  for attempt in 1 2 3 4 5 6; do
    rc=0
    # pipefail makes rc gh's exit code (0 pass, 1 fail, 8 pending)
    gh pr checks "$n" --watch --interval 15 2>&1 | tee "$TMP/checks.out" || rc=$?
    [[ "$rc" -eq 0 ]] && return 0
    if grep -qi "no checks reported" "$TMP/checks.out"; then
      sleep 10; continue
    fi
    return 1
  done
  return 1
}

ask() { # $1 prompt -> 0 yes
  local a; read -r -p "$1 [y/N] " a; [[ "$a" =~ ^[Yy]$ ]]
}

# ------------------------------------------------------------- merge loop
merged=(); skipped=()

for n in "${selected[@]}"; do
  echo
  echo "=== #$n: $(pr_field "$n" title) ==="

  if [[ "$(pr_field "$n" state)" != "OPEN" ]]; then
    echo "not open anymore; skipping"; skipped+=("#$n (not open)"); continue
  fi
  if [[ "$(pr_field "$n" isDraft)" == "true" ]]; then
    echo "draft; skipping (gh pr ready $n first)"; skipped+=("#$n (draft)"); continue
  fi
  base="$(pr_field "$n" baseRefName)"
  if [[ "$base" != "$BASE_BRANCH" ]]; then
    echo "base is '$base', not '$BASE_BRANCH' (stacked, its parent hasn't merged); skipping"
    skipped+=("#$n (stacked on $base)"); continue
  fi

  state="$(merge_state "$n")"
  echo "merge state: $state"

  if [[ "$state" == "DIRTY" ]]; then
    echo "merge conflicts; resolve manually"; skipped+=("#$n (conflicts)")
    ask "Continue with the remaining PRs?" && continue || break
  fi

  if [[ "$state" == "BEHIND" ]]; then
    old="$(pr_field "$n" headRefOid)"
    echo "branch is behind $BASE_BRANCH -> Update branch"
    upd=(gh pr update-branch "$n")
    [[ "$UPDATE_REBASE" -eq 1 ]] && upd+=(--rebase)
    if ! "${upd[@]}"; then
      skipped+=("#$n (update-branch failed)")
      ask "Continue with the remaining PRs?" && continue || break
    fi
    wait_for_new_head "$n" "$old" || echo "warning: head SHA didn't change after update"
  fi

  echo "waiting for checks..."
  if ! wait_for_checks "$n"; then
    echo "checks failed or never reported."
    echo "Reminder: a PR merges on its own diff; pre-existing breakage on untouched deployments is not this PR's."
    if ! ask "Attempt merge anyway (branch protection still applies)?"; then
      skipped+=("#$n (checks)")
      ask "Continue with the remaining PRs?" && continue || break
    fi
  fi

  mrg=(gh pr merge "$n" "--$METHOD")
  [[ "$DELETE_BRANCH" -eq 1 ]] && mrg+=(--delete-branch)
  if "${mrg[@]}"; then
    merged+=("#$n")
  else
    echo "merge of #$n failed"
    skipped+=("#$n (merge failed)")
    ask "Continue with the remaining PRs?" && continue || break
  fi
done

echo
echo "Merged : ${merged[*]:-none}"
echo "Skipped: ${skipped[*]:-none}"
