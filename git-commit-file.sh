#!/usr/bin/env sh
# git-commit-file.sh - automation for committing files to git

set -eu
[ "${DEBUG:-0}" = "1" ] && set -x

GIT_COMMIT_BRANCH="${GIT_COMMIT_BRANCH:-}"
GIT_COMMIT_MESSAGE="${GIT_COMMIT_MESSAGE:-Automated commit}"


_usage () {
    [ $# -gt 0 ] && echo "Error: $*" 1>&2
    cat <<EOUSAGE
Usage: $0 [OPTIONS] FILE [..]

Options:
  -b BRANCH         Branch to checkout
  -m MESSAGE        Git commit message
  -h                This screen
EOUSAGE
    exit 1
}

while getopts "b:m:h" args ; do
      case "$args" in
          b)    GIT_COMMIT_BRANCH="$OPTARG" ;;
          m)    GIT_COMMIT_MESSAGE="$OPTARG" ;;
          h)    _usage ;;
          *)    _usage "Invalid option '$args'" ;;
      esac
done
shift $((OPTIND-1))

[ $# -gt 0 ] || _usage "Missing file(s) to commit"

# Configure default name and email; needed to commit
if ! git config --get user.name >/dev/null ; then
    git config user.name "$GIT_USERNAME"
fi
if ! git config --get user.email >/dev/null ; then
    git config user.email "$GIT_EMAIL"
fi

# Add SSH host keys if they aren't already added
if [ -n "${GIT_KNOWN_HOSTS_ENTRY:-}" ] ; then
    firstword="$(echo "$GIT_KNOWN_HOSTS_ENTRY" | awk '{print $1}')"
    found=0
    for file in ~/.ssh/known_hosts /etc/ssh/ssh_known_hosts ; do
        if grep -qE "^$firstword""[[:space:]]" "$file" 2>/dev/null ; then
            found=1
        fi
    done
    if [ $found -eq 0 ] ; then
        mkdir -p ~/.ssh
        chmod 0700 ~/.ssh
        echo "$GIT_KNOWN_HOSTS_ENTRY" >> ~/.ssh/known_hosts
    fi
fi

# Fetch current origin so we can merge latest changes if needed
git fetch --all --prune --prune-tags --tags --recurse-submodules

# Checkout git branch if it was passed to this script as GIT_COMMIT_BRANCH
if [ -n "${GIT_COMMIT_BRANCH:-}" ] ; then

    git_branch="$GIT_COMMIT_BRANCH"
    git checkout "$GIT_COMMIT_BRANCH"

# Otherwise, set upstream tracking branch to current branch
else
    git_branch="$(git rev-parse --abbrev-ref HEAD)"

    # If branch doesn't exist in origin, push it; otherwise setting upstream
    # in next step won't work
    remote_head="$(git ls-remote --heads origin refs/heads/"${git_branch}")"
    if [ -z "$remote_head" ] ; then
        git push origin "${git_branch}:${git_branch}"
    fi

    # Set the upstream tracking branch
    git branch --set-upstream-to="origin/${git_branch}"
fi

# Merge the latest changes from the current branch, so we
# don't run into conflicts when trying to push our commit.
# This might fail if GIT_COMMIT_BRANCH is actually a commit hash
# and not a branch name
git merge --no-edit origin/"$git_branch"

# Add files specified and commit them, but only if they changed;
# otherwise the commands will return an error.
if git diff --quiet "$@" ; then
    echo "$0: Warning: git files unchanged; not adding/committing" 1>&2
else
    git add "$@"
    git commit -m "$GIT_COMMIT_MESSAGE"
fi

if ! git push -u ; then
  echo "git push failed, likely due to new changes being merged while this was running."
  echo "Automatically retrying"
  git pull --rebase
  git push -u
fi
