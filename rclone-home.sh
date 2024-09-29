#!/usr/bin/env bash
set -eu
[ "${DEBUG:-0}" = "1" ] && set -x

declare -a args=()

for i in "$@" ; do
    if [ "$i" = "--resync" ] ; then
        args+=("--resync")
    fi
done

for i in Documents Media ; do

    rclone \
        bisync \
        ./"$i"/ \
        googledrive:"$i"/ \
            --create-empty-src-dirs \
            --compare size,modtime,checksum \
            --slow-hash-sync-only \
            --resilient \
            -MvP \
            --fix-case \
            --drive-import-formats docx,odt \
            "${args[@]}"

done
