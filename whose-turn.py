#!/usr/bin/env python3
"""Dialog-based TUI that cross-references your open GitHub PRs and Linear issues to show whose turn it is."""
import argparse
import concurrent.futures
import getpass
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import textwrap
import threading
import time
from datetime import datetime, timezone
from pathlib import Path

APP_TITLE = "Whose Turn"
CACHE_DIR = Path.home() / ".cache" / "whose-turn"
CACHE_PATH = CACHE_DIR / "cache.json"
SEEN_PATH = CACHE_DIR / "seen.json"
CONFIG_PATH = Path.home() / ".config" / "whose-turn" / "config.json"
CANCEL = ("__cancel__", "Cancel")

BOT_LOGINS = {"github-actions", "linear", "dependabot", "renovate"}
LINEAR_ID_RE = re.compile(r'\b([A-Z][A-Z0-9]{1,9}-\d+)\b')

PR_FIELDS = ",".join([
    "number", "title", "url", "isDraft", "reviewDecision", "reviewRequests",
    "reviews", "comments", "commits", "headRefName", "body", "createdAt", "assignees",
])

# Priority tiers, also used to group checklist displays with divider rows.
GH_TIERS = [
    ("review_requested", "Review requested of you"),
    ("approved", "Approved — ready to merge"),
    ("changes_requested", "Changes requested"),
    ("comment", "Comment awaiting your response"),
    ("draft", "Draft"),
    ("review_requested_optional", "Already approved by someone else — optional"),
]
THEM_TIERS = [
    ("awaiting_review", "Awaiting first review"),
    ("awaiting_further_review", "Awaiting further review"),
    ("no_reviewer", "No reviewer requested yet"),
]
IN_PROGRESS_TIERS = [
    ("with_pr", "Has an open PR"),
    ("no_pr", "No linked PR"),
]

MAIN_HELP = (
    "Whose Turn tracks who needs to act next on your GitHub PRs and Linear issues.\n\n"
    "Get latest: run all GitHub/Linear queries and cache the result.\n"
    "See results: browse the cached data by category.\n"
    "Next GitHub/Linear item to work on: walk a single-item priority queue of what to do next.\n\n"
    "Nothing here modifies GitHub or Linear -- it's read-only."
)
SEE_RESULTS_HELP = (
    "Pick a category to see a checklist of its items, newest first. Rows starting with "
    "'-----' are group dividers only -- checking them does nothing."
)
ACTION_HELP = (
    "Open in browser opens every checked item's URL.\n"
    "Show full description shows the full PR body or Linear issue description for the checked items."
)
NEXT_HELP = (
    "Shows the single highest-priority item left in the queue (newest first within each "
    "priority tier). 'Next item' just advances the viewer -- it doesn't change anything in "
    "GitHub or Linear."
)


class FetchError(Exception):
    pass


# ---------- shell helpers ----------

def run(cmd):
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        raise FetchError(f"{' '.join(cmd)}\n{result.stderr.strip()}")
    return result.stdout


def is_bot(login):
    return login in BOT_LOGINS or login.endswith("[bot]")


def parse_ts(s):
    return datetime.fromisoformat(s.replace("Z", "+00:00"))


def age_str(iso):
    hours = (datetime.now(timezone.utc) - parse_ts(iso)).total_seconds() / 3600
    if hours < 1:
        return "<1h"
    if hours < 48:
        return f"{hours:.0f}h"
    return f"{hours / 24:.0f}d"


def chunked(seq, size):
    for i in range(0, len(seq), size):
        yield seq[i:i + size]


# ---------- config ----------

def load_config():
    if not CONFIG_PATH.exists():
        return {}
    return json.loads(CONFIG_PATH.read_text())


def save_config(cfg):
    CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
    CONFIG_PATH.write_text(json.dumps(cfg))


# ---------- data fetching ----------

def get_gh_login():
    data = json.loads(run(["gh", "api", "graphql", "-f", "query=query{viewer{login}}"]))
    return data["data"]["viewer"]["login"]


def get_linear_team_keys():
    out = run(["linear", "team", "list"])
    return {line.split()[0] for line in out.splitlines()[1:] if line.split()}


def extract_linear_ids(team_keys, *texts):
    ids = set()
    for t in texts:
        if t:
            for match in LINEAR_ID_RE.findall(t.upper()):
                if match.split("-", 1)[0] in team_keys:
                    ids.add(match)
    return ids


def fetch_my_open_prs():
    return json.loads(run([
        "gh", "pr", "list", "--author", "@me", "--state", "open",
        "--json", PR_FIELDS, "--limit", "30",
    ]))


def fetch_review_requested_prs():
    # draft:false -- a draft isn't actually ready for your review yet, even if requested
    out = run([
        "gh", "pr", "list", "--search", "review-requested:@me is:open draft:false",
        "--json", PR_FIELDS, "--limit", "30",
    ])
    return json.loads(out) if out.strip() else []


def linear_query(assignee, state_type):
    out = run([
        "linear", "issue", "query", "--assignee", assignee, "--state", state_type,
        "--all-teams", "--limit", "0", "--json",
    ])
    return json.loads(out)["nodes"]


def fetch_pr_attachments(ids):
    """identifier -> [{status, url, title, repo, number}] for every GitHub PR Linear has
    attached to the issue. This is authoritative regardless of which repo the PR lives in --
    unlike scanning PR bodies for a ticket ID, which only ever sees PRs in *this* repo."""
    result = {}
    for chunk in chunked(ids, 40):
        if not chunk:
            continue
        out = run(["linear", "api",
            "query($ids: [ID!]!) { issues(filter: {id: {in: $ids}}, first: 50) "
            "{ nodes { identifier attachments(first: 20) { nodes { sourceType metadata } } } } }",
            "--variables-json", json.dumps({"ids": chunk}),
        ])
        data = json.loads(out)
        if "errors" in data:
            continue
        for node in data["data"]["issues"]["nodes"]:
            prs = [
                {
                    "status": a["metadata"].get("status"),
                    "url": a["metadata"].get("url"),
                    "title": a["metadata"].get("title"),
                    "repo": a["metadata"].get("repoName"),
                    "number": a["metadata"].get("number"),
                }
                for a in node["attachments"]["nodes"]
                if a.get("sourceType") == "github"
            ]
            if prs:
                result[node["identifier"]] = prs
    return result


def fetch_blocking_relations(ids):
    """identifier -> [{identifier, title}] of open issues it blocks (forward 'blocks' relations)."""
    result = {}
    for chunk in chunked(ids, 40):
        if not chunk:
            continue
        out = run(["linear", "api",
            "query($ids: [ID!]!) { issues(filter: {id: {in: $ids}}, first: 50) "
            "{ nodes { identifier relations(first: 10) { nodes { type relatedIssue "
            "{ identifier title state { type } } } } } } }",
            "--variables-json", json.dumps({"ids": chunk}),
        ])
        data = json.loads(out)
        if "errors" in data:
            continue
        for node in data["data"]["issues"]["nodes"]:
            blocks = [
                {"identifier": r["relatedIssue"]["identifier"], "title": r["relatedIssue"]["title"]}
                for r in node["relations"]["nodes"]
                if r["type"] == "blocks" and r["relatedIssue"]["state"]["type"] not in ("completed", "canceled")
            ]
            if blocks:
                result[node["identifier"]] = blocks
    return result


def get_blockers(issue):
    """[identifier, ...] of open issues blocking this one (inverse 'blocks' relations)."""
    blockers = []
    for rel in issue.get("inverseRelations", {}).get("nodes", []):
        if rel.get("type") == "blocks":
            st = rel.get("issue", {}).get("state", {}).get("type")
            if st not in ("completed", "canceled"):
                blockers.append(rel["issue"]["identifier"])
    return blockers


def fetch_issue_description(identifier):
    out = run(["linear", "issue", "view", identifier, "--json"])
    return json.loads(out).get("description") or "(no description)"


# ---------- classification ----------

def classify_pr(pr, my_login):
    """Returns (turn, reason, reason_kind, activity_at_iso). turn is 'you' or 'them'."""
    if pr.get("isDraft"):
        return "you", "draft — mark ready for review when done", "draft", pr["createdAt"]

    reviewer_names = sorted({rr.get("login") or rr.get("name", "?") for rr in (pr.get("reviewRequests") or [])})

    # GitHub's reviewDecision doesn't clear on its own when you push a fix and re-request --
    # it only changes once the reviewer submits a new review. So a stale CHANGES_REQUESTED
    # from someone you've since re-requested isn't "your turn" anymore; the ball's on them.
    latest_review = {}
    for r in pr.get("reviews", []):
        login = r["author"]["login"]
        if login == my_login or is_bot(login):
            continue
        ts = parse_ts(r["submittedAt"])
        if login not in latest_review or ts > latest_review[login][0]:
            latest_review[login] = (ts, r["state"])

    outstanding_changes = {
        login: ts for login, (ts, state) in latest_review.items()
        if state == "CHANGES_REQUESTED" and login not in reviewer_names
    }
    if outstanding_changes:
        ts = max(outstanding_changes.values())
        return "you", f"changes requested by {', '.join(sorted(outstanding_changes))}", "changes_requested", ts.isoformat()

    decision = pr.get("reviewDecision") or ""
    if decision == "APPROVED":
        ap_reviews = [r for r in pr.get("reviews", []) if r["state"] == "APPROVED"]
        ts = max((r["submittedAt"] for r in ap_reviews), default=pr["createdAt"])
        return "you", "approved — ready to merge", "approved", ts

    non_you_events, you_events = [], []
    for r in pr.get("reviews", []):
        login = r["author"]["login"]
        ts = parse_ts(r["submittedAt"])
        if login == my_login:
            you_events.append(ts)
        elif not is_bot(login):
            non_you_events.append((ts, login))
    for c in pr.get("comments", []):
        login = c["author"]["login"]
        ts = parse_ts(c["createdAt"])
        if login == my_login:
            you_events.append(ts)
        elif not is_bot(login):
            non_you_events.append((ts, login))
    for commit in pr.get("commits", []):
        you_events.append(parse_ts(commit["committedDate"]))

    if not non_you_events:
        if reviewer_names:
            return "them", f"awaiting review from {', '.join(reviewer_names)}", "awaiting_review", pr["createdAt"]
        return "them", "no reviewer requested yet", "no_reviewer", pr["createdAt"]

    last_non_you_ts, last_non_you_login = max(non_you_events, key=lambda x: x[0])
    last_you = max(you_events) if you_events else parse_ts(pr["createdAt"])

    if last_non_you_ts > last_you:
        return "you", f"comment from {last_non_you_login} awaiting your response", "comment", last_non_you_ts.isoformat()
    reason = f"awaiting further review from {', '.join(reviewer_names)}" if reviewer_names else "awaiting further review"
    return "them", reason, "awaiting_further_review", last_you.isoformat()


def assigned_to_someone_else(pr, my_login):
    """True if the PR has assignees set and you're not one of them -- authoring/branch
    ownership doesn't make it "yours" if someone else has been explicitly assigned to drive it."""
    assignees = pr.get("assignees") or []
    return bool(assignees) and not any(a["login"] == my_login for a in assignees)


def classify_review_request(pr, my_login):
    """Returns (reason, reason_kind) for a PR where you're a requested reviewer."""
    approved_others = sorted({
        r["author"]["login"] for r in pr.get("reviews", [])
        if r["state"] == "APPROVED" and r["author"]["login"] != my_login
    })
    if approved_others:
        return f"review requested of you (already approved by {', '.join(approved_others)} — optional)", "review_requested_optional"
    return "review requested of you", "review_requested"


def issue_item(issue):
    return {
        "type": "issue", "identifier": issue["identifier"], "title": issue["title"],
        "url": issue["url"], "state": issue["state"]["name"], "updated_at": issue["updatedAt"],
    }


def run_parallel(tasks, on_done=None):
    """tasks: {name: callable}. Returns {name: result}; a raised exception propagates
    from .result() once every task has been collected."""
    if not tasks:
        return {}
    results = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=len(tasks)) as pool:
        futures = {pool.submit(fn): name for name, fn in tasks.items()}
        for future in concurrent.futures.as_completed(futures):
            name = futures[future]
            results[name] = future.result()
            if on_done:
                on_done(name)
    return results


def build_snapshot(linear_assignee, progress=None):
    def p(pct, text):
        if progress:
            progress(pct, text)

    p(5, "Getting GitHub login and Linear team keys...")
    base = run_parallel({"my_login": get_gh_login, "team_keys": get_linear_team_keys})
    my_login, team_keys = base["my_login"], base["team_keys"]

    fetch_tasks = {
        "my_prs": fetch_my_open_prs,
        "review_requested_prs": fetch_review_requested_prs,
        "started_issues": lambda: linear_query(linear_assignee, "started"),
        "todo_issues": lambda: linear_query(linear_assignee, "unstarted"),
    }
    done = 0

    def on_done(name):
        nonlocal done
        done += 1
        p(15 + round(55 * done / len(fetch_tasks)), f"Fetched {name} ({done}/{len(fetch_tasks)})")

    p(15, f"Fetching {len(fetch_tasks)} data sources in parallel...")
    fresh = run_parallel(fetch_tasks, on_done=on_done)

    my_prs = fresh["my_prs"]
    review_requested_prs = fresh["review_requested_prs"]
    started_issues = fresh["started_issues"]
    todo_issues = fresh["todo_issues"]

    p(75, "Checking Linear blocking relations and attached PRs...")
    started_ids = [i["identifier"] for i in started_issues]
    blocking_map = fetch_blocking_relations(started_ids)
    pr_attachments = fetch_pr_attachments(started_ids)

    p(92, "Classifying...")

    your_turn, their_turn = [], []
    for pr in my_prs:
        if assigned_to_someone_else(pr, my_login):
            continue
        turn, reason, reason_kind, activity_at = classify_pr(pr, my_login)
        tickets = sorted(extract_linear_ids(team_keys, pr.get("body"), pr.get("headRefName")))
        item = {
            "type": "pr", "number": pr["number"], "title": pr["title"], "url": pr["url"],
            "body": pr.get("body") or "", "reason": reason, "reason_kind": reason_kind,
            "created_at": pr["createdAt"], "activity_at": activity_at, "tickets": tickets,
        }
        (your_turn if turn == "you" else their_turn).append(item)

    for pr in review_requested_prs:
        tickets = sorted(extract_linear_ids(team_keys, pr.get("body"), pr.get("headRefName")))
        reason, reason_kind = classify_review_request(pr, my_login)
        your_turn.append({
            "type": "pr", "number": pr["number"], "title": pr["title"], "url": pr["url"],
            "body": pr.get("body") or "", "reason": reason, "reason_kind": reason_kind,
            "created_at": pr["createdAt"], "activity_at": pr["createdAt"], "tickets": tickets,
        })

    closeable, in_progress_with_pr, in_progress_no_pr = [], [], []
    blocked_list, blocking_others = [], []
    for issue in started_issues:
        item = issue_item(issue)
        blockers = get_blockers(issue)
        blocks = blocking_map.get(issue["identifier"], [])
        item["blocked_by"] = blockers
        item["blocks"] = blocks
        if blockers:
            blocked_list.append(item)
        if not blockers and blocks:
            blocking_others.append(item)

        prs = pr_attachments.get(issue["identifier"], [])
        open_prs = [pr for pr in prs if pr["status"] == "open"]
        merged_prs = [pr for pr in prs if pr["status"] == "merged"]
        if open_prs:
            item["prs"] = open_prs
            in_progress_with_pr.append(item)
        elif merged_prs:
            item["prs"] = merged_prs
            closeable.append(item)
        else:
            in_progress_no_pr.append(item)

    todo = [issue_item(i) for i in todo_issues]

    your_turn.sort(key=lambda x: x["activity_at"], reverse=True)
    their_turn.sort(key=lambda x: x["activity_at"], reverse=True)
    for lst in (closeable, in_progress_with_pr, in_progress_no_pr, blocked_list, blocking_others, todo):
        lst.sort(key=lambda x: x["updated_at"], reverse=True)

    p(100, "Done")
    return {
        "fetched_at": datetime.now(timezone.utc).isoformat(),
        "linear_assignee": linear_assignee,
        "your_turn": your_turn,
        "their_turn": their_turn,
        "closeable": closeable,
        "in_progress_with_pr": in_progress_with_pr,
        "in_progress_no_pr": in_progress_no_pr,
        "blocked": blocked_list,
        "blocking_others": blocking_others,
        "todo": todo,
    }


def _atomic_write_json(path, data):
    """A background refresh thread may write this while the TUI is reading it."""
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(data))
    tmp.replace(path)


def _read_json(path):
    if not path.exists():
        return None
    return json.loads(path.read_text())


def save_cache(data):
    _atomic_write_json(CACHE_PATH, data)


def load_cache():
    return _read_json(CACHE_PATH)


ALL_BUCKETS = (
    "your_turn", "their_turn", "closeable", "in_progress_with_pr",
    "in_progress_no_pr", "blocked", "blocking_others", "todo",
)


def item_key(item):
    return f"pr:{item['number']}" if item["type"] == "pr" else f"issue:{item['identifier']}"


def build_fingerprints(data):
    """item key -> a string that changes whenever anything checklist_label would show
    changes (reason, state, linked PR, blockers, ...)."""
    return {
        item_key(item): checklist_label(item)
        for bucket in ALL_BUCKETS for item in data.get(bucket, [])
    }


def count_changed(data, seen):
    current = build_fingerprints(data)
    return sum(1 for key, label in current.items() if seen.get(key) != label)


def load_seen():
    return _read_json(SEEN_PATH) or {}


def mark_seen(data):
    _atomic_write_json(SEEN_PATH, build_fingerprints(data))


def fmt_fetched_at(data):
    try:
        return parse_ts(data["fetched_at"]).astimezone().strftime("%Y-%m-%d %H:%M")
    except Exception:
        return "unknown"


# ---------- grouping (for checklist divider rows and priority queues) ----------

def group_rows(items, tiers, key_fn):
    """Returns [("header", label), ("item", item), ...] ordered by tiers, dividing each group."""
    buckets = {}
    for it in items:
        buckets.setdefault(key_fn(it), []).append(it)
    rows = []
    for key, label in tiers:
        bucket = buckets.pop(key, [])
        if not bucket:
            continue
        rows.append(("header", f"----- {label.upper()} -----"))
        rows.extend(("item", it) for it in bucket)
    for key, bucket in buckets.items():
        if bucket:
            rows.append(("header", f"----- {key.upper()} -----"))
            rows.extend(("item", it) for it in bucket)
    return rows


def flat_rows(items):
    return [("item", it) for it in items]


def github_priority_queue(data):
    queue = []
    for key, _ in GH_TIERS:
        tier_items = [i for i in data["your_turn"] if i["reason_kind"] == key]
        queue.extend(sorted(tier_items, key=lambda x: x["activity_at"], reverse=True))
    return queue


def linear_priority_queue(data):
    tiers = [data["closeable"], data["blocking_others"], data["in_progress_no_pr"], data["todo"]]
    queue = []
    for tier in tiers:
        queue.extend(sorted(tier, key=lambda x: x["updated_at"], reverse=True))
    return queue


# ---------- dialog primitives ----------

# Rows dialog needs beyond the list itself for a --menu/--checklist box: title, top/bottom
# borders, the blank line above and below the prompt text, and the button row. Padded a
# couple of rows beyond the theoretical minimum -- underestimating this crashes dialog
# ("Can't make sub-window"), which looks exactly like the user pressing Cancel.
LIST_OVERHEAD = 10


def screen_size():
    cols, lines = shutil.get_terminal_size(fallback=(100, 30))
    return max(cols - 4, 60), max(lines - 4, 20)


def list_height(h, n):
    return max(1, min(n, h - LIST_OVERHEAD))


TIMEOUT = "__timeout__"
# dialog's own idle-timeout, not an externally sent signal: it exits through its normal cleanup
# path (same as Cancel/OK) after this many idle seconds, so we can redraw with fresh data --
# verified this restores the terminal exactly as cleanly as any other dialog exit.
DIALOG_TIMEOUT_EXIT_CODE = 5


def run_dialog(args, env=None):
    result = subprocess.run(["dialog", "--stdout"] + args, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, env=env)
    return result.returncode, result.stdout


def menu(text, items, dialog_title=APP_TITLE, help_text=None, idle_timeout=None):
    w, h = screen_size()
    list_h = list_height(h, len(items))
    args = ["--backtitle", APP_TITLE, "--title", dialog_title]
    if help_text:
        args += ["--help-button"]
    env = None
    if idle_timeout:
        args += ["--timeout", str(idle_timeout)]
        env = {**os.environ, "DIALOG_TIMEOUT": str(DIALOG_TIMEOUT_EXIT_CODE)}
    args += ["--menu", text, str(h), str(w), str(list_h)]
    for tag, item_text in items:
        args += [tag, item_text]
    while True:
        rc, out = run_dialog(args, env=env)
        if help_text and rc == 2:
            msgbox(help_text, title="Help")
            continue
        if idle_timeout and rc == DIALOG_TIMEOUT_EXIT_CODE:
            return TIMEOUT
        if rc != 0:
            return None
        return out.strip() or None


def checklist(text, entries, dialog_title=APP_TITLE, help_text=None):
    w, h = screen_size()
    list_h = list_height(h, len(entries))
    args = ["--backtitle", APP_TITLE, "--title", dialog_title, "--separate-output"]
    if help_text:
        args += ["--help-button"]
    args += ["--checklist", text, str(h), str(w), str(list_h)]
    for tag, item_text, checked in entries:
        args += [tag, item_text, "on" if checked else "off"]
    while True:
        rc, out = run_dialog(args)
        if help_text and rc == 2:
            msgbox(help_text, title="Help")
            continue
        if rc != 0:
            return None
        return [line for line in out.splitlines() if line.strip()]


def msgbox(text, title=""):
    w, h = screen_size()
    run_dialog(["--title", title, "--msgbox", text, str(h), str(w)])


def textbox(text, title=""):
    w, h = screen_size()
    with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False) as f:
        f.write(text)
        path = f.name
    try:
        run_dialog(["--title", title, "--textbox", path, str(h), str(w)])
    finally:
        Path(path).unlink(missing_ok=True)


def inputbox(text, default=""):
    w, _ = screen_size()
    rc, out = run_dialog(["--title", APP_TITLE, "--inputbox", text, "10", str(min(w, 80)), default])
    if rc != 0:
        return None
    return out.strip()


def print_progress(pct, text):
    """Plain-terminal progress line -- avoids a nested dialog subprocess (gauge) whose
    stdin-EOF-triggers-exit behavior turned out to hang under some terminal setups."""
    print(f"[{pct:3d}%] {text}")
    sys.stdout.flush()


# ---------- rendering ----------

def checklist_label(item):
    if item["type"] == "pr":
        label = f"#{item['number']} {item['title']} — {item['reason']} ({age_str(item['activity_at'])})"
        if item.get("tickets"):
            label += f" [{', '.join(item['tickets'])}]"
    else:
        label = f"{item['identifier']} {item['title']} [{item['state']}] ({age_str(item['updated_at'])})"
        if item.get("blocked_by"):
            label += f" — blocked by {', '.join(item['blocked_by'])}"
        if item.get("blocks"):
            label += f" — blocks {', '.join(b['identifier'] for b in item['blocks'])}"
        if item.get("prs"):
            label += f" — PR: {join_capped(pr_label(pr) for pr in item['prs'])}"
    return label[:200]


def pr_label(pr):
    return f"{pr['repo']}#{pr['number']} [{pr['status']}]"


def join_capped(values, limit=5):
    values = list(values)
    shown = ", ".join(values[:limit])
    if len(values) > limit:
        shown += f" (+{len(values) - limit} more)"
    return shown


def item_lines(item):
    """Priority-ordered header/meta lines for the item (most important first)."""
    if item["type"] == "pr":
        lines = [f"PR #{item['number']}: {item['title']}", f"Reason: {item['reason']}"]
        if item.get("tickets"):
            lines.append(f"Linear: {join_capped(item['tickets'])}")
        lines.append(f"URL: {item['url']}")
        lines.append(f"Created: {item['created_at']}")
    else:
        lines = [f"{item['identifier']}: {item['title']}", f"State: {item.get('state', '')}"]
        if item.get("blocked_by"):
            lines.append(f"Blocked by: {join_capped(item['blocked_by'])}")
        if item.get("blocks"):
            lines.append(f"Blocks: {join_capped(b['identifier'] for b in item['blocks'])}")
        if item.get("prs"):
            for pr in item["prs"]:
                lines.append(f"PR: {pr_label(pr)} {pr['title']} {pr['url']}")
        lines.append(f"URL: {item['url']}")
        lines.append(f"Updated: {item.get('updated_at', '')}")
    return lines


def item_header_meta(item):
    return "\n".join(item_lines(item))


def item_body(item):
    if item["type"] == "pr":
        return item.get("body") or "(no description)"
    try:
        return fetch_issue_description(item["identifier"])
    except FetchError as e:
        return f"(failed to fetch description: {e})"


def full_text(item):
    return f"{item_header_meta(item)}\n\n{item_body(item)}"


TRUNCATION_NOTICE = "... (truncated -- choose 'Show full description' for the rest)"


def wrap_lines(text, wrap_width):
    wrapped = []
    for line in text.splitlines() or [""]:
        wrapped.extend(textwrap.wrap(line, wrap_width) or [""])
    return wrapped


def summary_text(item, width, max_total_lines):
    """Fits within an exact wrapped-line budget (header AND body) -- dialog's --menu
    hard-crashes ("Can't make sub-window") if the prompt text has more wrapped lines than
    fit above the button list, and that crash looks exactly like the user pressing Cancel.
    Header lines are cut first if even they don't fit; body is truncated after that."""
    wrap_width = max(20, width - 6)
    max_total_lines = max(1, max_total_lines)

    header_wrapped = []
    for line in item_lines(item):
        header_wrapped.extend(textwrap.wrap(line, wrap_width) or [""])
    if len(header_wrapped) >= max_total_lines:
        return "\n".join(header_wrapped[:max_total_lines])

    remaining = max_total_lines - len(header_wrapped) - 1  # -1 for the blank separator line
    body_wrapped = wrap_lines(item_body(item), wrap_width)
    if len(body_wrapped) > remaining:
        notice_lines = (textwrap.wrap(TRUNCATION_NOTICE, wrap_width) or [TRUNCATION_NOTICE])[:remaining]
        limit = max(0, remaining - len(notice_lines))
        body_lines = body_wrapped[:limit] + notice_lines
    else:
        body_lines = body_wrapped
    if not body_lines:
        return "\n".join(header_wrapped)
    return "\n".join(header_wrapped) + "\n\n" + "\n".join(body_lines)


def show_descriptions(items):
    divider = "\n\n" + ("-" * 60) + "\n\n"
    textbox(divider.join(full_text(i) for i in items), title="Description")


def open_urls(items):
    for item in items:
        subprocess.run(["open", item["url"]])


# ---------- TUI flow ----------

def item_action_menu(selected_items):
    while True:
        choice = menu(
            "Choose an action for the checked item(s):",
            [CANCEL, ("open", "Open in browser"), ("desc", "Show full description")],
            dialog_title="Action", help_text=ACTION_HELP,
        )
        if choice in (None, CANCEL[0]):
            return
        if choice == "open":
            open_urls(selected_items)
            return
        elif choice == "desc":
            show_descriptions(selected_items)


def category_checklist(title, rows, help_text):
    real_items = [payload for kind, payload in rows if kind == "item"]
    if not real_items:
        msgbox("Nothing here.", title=title)
        return
    while True:
        entries = []
        idx = 0
        for kind, payload in rows:
            if kind == "header":
                entries.append((f"hdr_{len(entries)}", payload, False))
            else:
                entries.append((f"i_{idx}", checklist_label(payload), False))
                idx += 1
        selected_tags = checklist("Check items, then OK to act on them:", entries, dialog_title=title, help_text=help_text)
        if selected_tags is None:
            return
        chosen = [real_items[int(t.split("_", 1)[1])] for t in selected_tags if t.startswith("i_")]
        if not chosen:
            continue
        item_action_menu(chosen)


def count_items(rows):
    return sum(1 for kind, _ in rows if kind == "item")


def sectioned_rows(sections):
    """[(label, rows), ...] -> one combined row list, each non-empty section getting its own
    '===== LABEL =====' divider (tiers within a section keep their own '----- ' divider)."""
    rows = []
    for label, section_rows in sections:
        if not count_items(section_rows):
            continue
        rows.append(("header", f"===== {label.upper()} ====="))
        rows.extend(section_rows)
    return rows


def your_turn_rows(data):
    """Your open PRs needing action, plus Linear tickets where the action is yours too:
    ready to close, or blocking other tickets."""
    return sectioned_rows([
        ("Your PRs", group_rows(data["your_turn"], GH_TIERS, lambda i: i["reason_kind"])),
        ("Linear: probably ready to close", flat_rows(data["closeable"])),
        ("Linear: blocking other tickets", flat_rows(data["blocking_others"])),
    ])


def everything_else_rows(data):
    """Everything waiting on someone/something other than you."""
    in_progress_items = sorted(
        [dict(it, _group="with_pr") for it in data["in_progress_with_pr"]]
        + [dict(it, _group="no_pr") for it in data["in_progress_no_pr"]],
        key=lambda x: x["updated_at"], reverse=True,
    )
    return sectioned_rows([
        ("Waiting on others", group_rows(data["their_turn"], THEM_TIERS, lambda i: i["reason_kind"])),
        ("Linear: in progress / code review", group_rows(in_progress_items, IN_PROGRESS_TIERS, lambda i: i["_group"])),
        ("Linear: blocked", flat_rows(data["blocked"])),
    ])


def see_results_menu():
    data = load_cache()
    if data is None:
        msgbox("No cached results yet. Run 'Get latest' first.")
        return
    mark_seen(data)  # visiting here is what resets the "N items changed" count on the main menu

    yt_rows = your_turn_rows(data)
    other_rows = everything_else_rows(data)
    todo_rows = flat_rows(data["todo"])

    while True:
        choice = menu(
            "Choose a view:",
            [
                CANCEL,
                ("your_turn", f"Your turn ({count_items(yt_rows)})"),
                ("everything_else", f"Everything else ({count_items(other_rows)})"),
                ("todo", f"Todo ({count_items(todo_rows)})"),
            ],
            dialog_title=f"See Results (fetched {fmt_fetched_at(data)})", help_text=SEE_RESULTS_HELP,
        )
        if choice in (None, CANCEL[0]):
            return
        if choice == "your_turn":
            category_checklist(
                "Your turn", yt_rows,
                "Where you need to act: respond to a review request, merge an approval, address "
                "changes requested, answer a comment, close a done ticket, or unblock a ticket "
                "that's blocking others. Grouped by priority tier / category.",
            )
        elif choice == "everything_else":
            category_checklist(
                "Everything else", other_rows,
                "Everything waiting on someone/something other than you: PRs waiting on a "
                "reviewer, and Linear tickets in progress or blocked. '=====' rows are category "
                "dividers, '-----' rows are sub-group dividers within a category -- checking "
                "either does nothing.",
            )
        elif choice == "todo":
            category_checklist("Todo", todo_rows, "Linear tickets not yet started.")


REFRESH_INTERVAL_SECONDS = 60


def start_background_refresh(linear_assignee):
    """Daemon thread: silently re-fetch every REFRESH_INTERVAL_SECONDS so whichever menu
    you're in next picks up new data. Dies with the process -- no shutdown needed."""
    def loop():
        while True:
            time.sleep(REFRESH_INTERVAL_SECONDS)
            try:
                save_cache(build_snapshot(linear_assignee))
            except FetchError:
                pass  # keep the last good cache; try again next interval

    threading.Thread(target=loop, daemon=True).start()


def do_get_latest(linear_assignee):
    print(f"\nFetching latest data for '{linear_assignee}'...")
    try:
        data = build_snapshot(linear_assignee, progress=print_progress)
    except FetchError as e:
        msgbox(str(e), title="Fetch failed")
        return
    save_cache(data)
    msgbox(
        f"Fetched at {fmt_fetched_at(data)}\n\n"
        f"Your turn: {len(data['your_turn'])}\n"
        f"Waiting on others: {len(data['their_turn'])}\n"
        f"Linear ready to close: {len(data['closeable'])}\n"
        f"Linear in progress w/ PR: {len(data['in_progress_with_pr'])}\n"
        f"Linear in progress no PR: {len(data['in_progress_no_pr'])}\n"
        f"Linear blocked: {len(data['blocked'])}\n"
        f"Linear blocking others: {len(data['blocking_others'])}\n"
        f"Linear todo: {len(data['todo'])}",
        title="Fetched",
    )


def next_item_viewer(build_queue, label):
    data = load_cache()
    if data is None:
        msgbox("No cached results yet. Run 'Get latest' first.")
        return
    queue = build_queue(data)
    if not queue:
        msgbox("Nothing pending.", title=f"Next {label}")
        return
    index = 0
    while True:
        item = queue[index]
        menu_items = [CANCEL, ("open", "Open in browser"), ("desc", "Show full description")]
        if index + 1 < len(queue):
            menu_items.append(("next", "Next item"))
        w, h = screen_size()
        list_h = list_height(h, len(menu_items))
        max_total_lines = h - list_h - LIST_OVERHEAD
        choice = menu(
            summary_text(item, w, max_total_lines), menu_items,
            dialog_title=f"Next {label} to work on ({index + 1}/{len(queue)})", help_text=NEXT_HELP,
        )
        if choice in (None, CANCEL[0]):
            return
        if choice == "open":
            open_urls([item])
        elif choice == "desc":
            show_descriptions([item])
        elif choice == "next":
            index += 1


MAIN_MENU_IDLE_SECONDS = 15  # redraw with fresh counts if you're just sitting at the main menu


def main_menu(linear_assignee):
    while True:
        text = "Choose an action:"
        data = load_cache()
        if data is not None:
            changed = count_changed(data, load_seen())
            if changed:
                plural = "s" if changed != 1 else ""
                text += f"\n\n{changed} item{plural} changed since you last checked 'See results'."
        choice = menu(
            text,
            [
                ("see_results", "See results (cached)"),
                ("next_gh", "Next GitHub item to work on"),
                ("next_linear", "Next Linear item to work on"),
                ("get_latest", "Get latest (run queries)"),
                CANCEL,
            ],
            dialog_title=APP_TITLE, help_text=MAIN_HELP, idle_timeout=MAIN_MENU_IDLE_SECONDS,
        )
        if choice == TIMEOUT:
            continue
        if choice in (None, CANCEL[0]):
            return
        if choice == "get_latest":
            do_get_latest(linear_assignee)
        elif choice == "see_results":
            see_results_menu()
        elif choice == "next_gh":
            next_item_viewer(github_priority_queue, "GitHub")
        elif choice == "next_linear":
            next_item_viewer(linear_priority_queue, "Linear")


def resolve_linear_assignee(cli_value, config, non_interactive):
    if cli_value:
        return cli_value
    if config.get("linear_assignee"):
        return config["linear_assignee"]
    if non_interactive:
        return getpass.getuser()
    return inputbox("Linear assignee (displayName) to track:", default=getpass.getuser()) or getpass.getuser()


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--linear-assignee", default=None, help="Linear displayName to query (overrides saved config)")
    ap.add_argument("--json", action="store_true", help="Fetch, cache, and dump raw JSON (no TUI)")
    args = ap.parse_args()

    if not args.json and shutil.which("dialog") is None:
        sys.stderr.write("This tool requires the 'dialog' utility. Install with: brew install dialog\n")
        sys.exit(1)

    config = load_config()
    linear_assignee = resolve_linear_assignee(args.linear_assignee, config, non_interactive=args.json)
    if linear_assignee != config.get("linear_assignee"):
        save_config({**config, "linear_assignee": linear_assignee})

    if args.json:
        try:
            data = build_snapshot(linear_assignee)
        except FetchError as e:
            sys.stderr.write(f"{e}\n")
            sys.exit(1)
        save_cache(data)
        print(json.dumps(data, indent=2))
        return

    do_get_latest(linear_assignee)
    start_background_refresh(linear_assignee)
    main_menu(linear_assignee)


if __name__ == "__main__":
    main()
