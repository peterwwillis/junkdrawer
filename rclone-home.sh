#!/usr/bin/env bash
set -eu
[ "${DEBUG:-0}" = "1" ] && set -x

_run_rclone_bisync () {
    local remote="$1"; shift
    for dir in "${localdirs[@]}" ; do
        rclone \
                --verbose \
                --progress \
                bisync \
                ./"$dir"/ \
                "$remote":"$dir"/ \
                    --fast-list \
                    --resilient \
                    --create-empty-src-dirs \
                    --no-update-modtime \
                    --metadata \
                    --drive-use-trash=true \
                    --drive-export-formats=ods,odt,odp \
                    --drive-import-formats=ods,odt,odp \
                    "${rcloneargs[@]}"
    done
}

_run_rclone_remotes () {
    for remote in "${remotes[@]}" ; do
        _run_rclone_bisync "$remote"
    done
}

# Extra args to rclone.
# To add based on your system and version of rclone:
#   --fix-case
#   --slow-hash-sync-only
declare -a rcloneargs=()

# RClone Remotes must start with 'home-'
declare -a remotes=( $( rclone listremotes | sed -E 's/:$//g' | grep '^home-' ) )

declare -a localdirs=( Documents ) # Media Music Pictures )

while getopts "hR" args ; do
    case "$args" in
        h)        _usage ;;
        R)        rcloneargs+=("--resync") ;;
        *)        echo "$0: Error: invalid args '$args'" ; exit 1 ;;
    esac    
done                
shift $((OPTIND-1))

_run_rclone_remotes
