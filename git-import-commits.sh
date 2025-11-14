#!/usr/bin/env sh
# git-import-commits.sh - imports a tarball of patches as git commits
set -eu
[ "${DEBUG:-0}" = "1" ] && set -x

_die () { printf "%s: %s\n" "$0" "$*" 1>&2 ; exit 1 ; }
_usage () {
    cat <<EOUSAGE
Usage: $0 DST_GIT_REPO [INPUT_FILE]

Imports patches from tarball INPUT_FILE into DST_GIT_REPO.

Options:
    -i FILE             Input file
    -3                  Add '-3' option to 'git am' (3-way merge)
    -h                  This screen
EOUSAGE
    exit 1
}

if [ $# -lt 1 ] ; then
    _usage
fi

input_file="" _git_am_3way=""

while getopts "h3i:" arg ; do
    case "$arg" in
        i)          input_file="$OPTARG" ;;
        3)          _git_am_3way="-3" ;;
        h)          _usage ;;
        *)          _die "Unknown argument '$arg'" ;;
    esac
done
shift $((OPTIND-1))

dst_git_repo="$1" input_file="${input_file:-${2:-}}"

if [ -z "$input_file" ] ; then
    _die "Error: need to specify an input file"
fi


tmpdir="$(mktemp -d)"
cd "$dst_git_repo"

tar -C "$tmpdir" -xf "$input_file"
set +e
git am $_git_am_3way "$tmpdir"/*.patch
ret=$?
rm -rf "$tmpdir"
exit "$ret"
