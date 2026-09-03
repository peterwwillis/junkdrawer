#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: $0 <branch-name> [PR title]"
    echo "  Creates a new branch, pushes, creates PR, merges to main, cleans up."
    exit 1
}

detect_cli() {
    local remote_url
    remote_url=$(git remote get-url origin 2>/dev/null || echo "")

    if [[ "$remote_url" == *"github.com"* ]]; then
        echo "gh"
    elif [[ "$remote_url" == *"codeberg.org"* ]] ; then
        echo "fj"
    else
        echo "$0: ERROR: Unfamiliar remote URL '$remote_url'; exiting" 1>&2
        exit 1
    fi
}

check_cli() {
    local cli="$1"
    if ! command -v "$cli" &>/dev/null; then
        echo "$0: ERROR: $cli is not installed" 1>&2
        exit 1
    fi
}

get_main_branch() {
    local main_branch
    if git show-ref --verify --quiet refs/heads/main 2>/dev/null; then
        main_branch="main"
    elif git show-ref --verify --quiet refs/heads/master 2>/dev/null; then
        main_branch="master"
    else
        echo "$0: ERROR: Could not find main or master branch" 1>&2
        exit 1
    fi
    echo "$main_branch"
}

main() {
    if [[ $# -lt 1 ]]; then
        usage
    fi

    local branch_name="$1"
    local pr_title="${2:-}"
    local current_branch
    local cli
    local main_branch

    current_branch="$(git branch --show-current)"
    if [[ -z "$current_branch" ]]; then
        echo "$0: ERROR: Cannot determine current branch (detached HEAD state)" 1>&2
        exit 1
    fi

    main_branch="$(get_main_branch)"

    if [[ "$current_branch" != "$main_branch" ]]; then
        echo "$0: ERROR: Must be on $main_branch to run this script" 1>&2
        exit 1
    fi

    cli="$(detect_cli)"
    check_cli "$cli"

    echo "Detected remote type: $cli"
    echo "Creating branch: $branch_name"

    git checkout -b "$branch_name"

    echo "Pushing branch to remote..."
    git push -u origin "$branch_name"

    echo "Creating pull request..."
    if [[ -n "$pr_title" ]]; then
        if [[ "$cli" == "gh" ]]; then
            gh pr create --title "$pr_title" --body ""
        elif [[ "$cli" == "fj" ]]; then
            fj pr create "$pr_title" --body ""
        fi
    else
        if [[ "$cli" == "gh" ]]; then
            gh pr create --fill
        elif [[ "$cli" == "fj" ]]; then
            fj pr create --autofill
        fi
    fi

    echo "Merging pull request..."
    if [[ "$cli" == "gh" ]]; then
        gh pr merge --delete-branch --auto
    elif [[ "$cli" == "fj" ]]; then
        fj pr merge --delete --method merge
    fi

    echo "Switching to $main_branch branch..."
    git checkout "$main_branch"

    echo "Updating $main_branch branch..."
    git pull origin "$main_branch"

    echo "Cleaning up local branch..."
    git branch -d "$branch_name"

    echo "Returning to original branch: $current_branch"
    git checkout "$current_branch"

    echo "Done!"
}

main "$@"
