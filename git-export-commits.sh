#!/usr/bin/env sh
set -eu
[ "${DEBUG:-0}" = "1" ] && set -x

_die () { printf "%s: %s\n" "$0" "$*" 1>&2 ; exit 1 ; }
_usage () {
    cat <<EOUSAGE
Usage: $0 SRC_GIT_REPO [START_COMMIT [END_COMMIT]]

Exports commits from START_COMMIT to END_COMMIT from SRC_GIT_REPO
and tars them up into OUTPUT_FILE.

Options:
    -o FILE             Output file
    -f                  Use the repo's first commit
    -l                  Use the repo's last commit
    -h                  This screen
EOUSAGE
    exit 1
}

if [ $# -lt 1 ] ; then
    _usage
fi

_use_first_commit=0 _use_last_commit=0
output_file=""

while getopts "hlfo:" arg ; do
    case "$arg" in
        o)          output_file="$OPTARG" ;;
        f)          _use_first_commit=1 ;;
        l)          _use_last_commit=1 ;;
        h)          _usage ;;
        *)          _die "Unknown argument '$arg'" ;;
    esac
done
shift $((OPTIND-1))

src_git_repo="$1" start_commit="${2:-}" end_commit="${3:-}"

if [ -z "$start_commit" ] ; then
    if [ "$_use_first_commit" -eq 1 ] ; then
        start_commit="$(git rev-list --max-parents=0 HEAD)"
    fi
fi

if [ -z "$end_commit" ] ; then
    if [ "$_use_last_commit" -eq 1 ] ; then
        end_commit="$(git rev-parse HEAD)"
    fi
fi

if [ -z "$start_commit" ] || [ -z "$end_commit" ] ; then
    _die "Error: need to specify both start and end commit (or -f and/or -l)"
fi

[ -n "$output_file" ] || output_file="git-commit-export-$(date +"%Y-%m-%d_%H-%M-%S_$RANDOM").tar.gz"


tmpdir="$(mktemp -d)"
cd "$src_git_repo"
# The ^ is necessary to include the commit specified by START_COMMIT
#git format-patch -o "$tmpdir" "$start_commit"^.."$end_commit"
git format-patch -o "$tmpdir" "$start_commit".."$end_commit"
tar -C "$tmpdir" -cf - . | gzip -9 > "$output_file"
rm -rf "$tmpdir"
