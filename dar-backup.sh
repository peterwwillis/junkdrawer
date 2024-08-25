#!/usr/bin/env sh
# dar-backup.sh - generate a full and/or incremental backup using dar
set -eu
[ "${DEBUG:-0}" = "1" ] && set -x


BACKUP_DIR="$HOME/.Backup/"


_main () {

    [ -d "$BACKUP_DIR" ] || mkdir -p "$BACKUP_DIR"
    BACKUP_DIR="$(cd "$BACKUP_DIR" && pwd -P)"
    mkdir -p "$BACKUP_DIR"

    if [ $# -lt 1 ] || [ "${1:-}" = "-h" ] ; then
        cat <<EOUSAGE
Usage: $0 FILE [..]

Make an incremental or full (if one doesn't exist yet) backup of a FILE (can be
a directory), using Dar.

This script will create a backup directory ~/.Backup/ to store your backups in.
Backups are stored in a hierarchical file tree based on year and month.
The basename of DIR is the name of the backup file.

If no full backup has been taken this year, a full backup of DIR is taken.
Otherwise, an incremental backup is taken.

There is no limit on the number of backups, so the more you run this script,
the more incremental backups will pop up, but they will only be 24kB if nothing
has changed.

nice and ionice are used to lower the CPU and IO priorities as much as possible.
EOUSAGE
        exit 1
    fi

    for dir in "$@" ; do
        _run_dar_single_dir "$dir"
    done
}

_run_dar () {
    nice -n 19 \
        ionice -c 3 -t \
            dar \
                --no-overwrite \
                --quiet \
                "$@" \
                --compression=zstd \
                --alter="no-case" \
                -Z "*.gz" -Z "*.tgz" -Z "*.bz2" -Z "*.tbz2" -Z "*.xz" -Z "*.txz" -Z "*.zip" -Z "*.png" -Z "*.jpg" -Z "*.jpeg" -Z "*.avi" -Z "*.mpg" -Z "*.mpeg" -Z "*.mp3"
}

_run_dar_single_dir () {
    dir="$1"; shift
    dir_basename="$(basename "$dir")"

    fullfilename="$( _generate_dar_full_backup_filename "$dir_basename" )"

    # If no matching 'full backup' is found, run a full backup
    if ! ls "$fullfilename".*.dar 2>/dev/null 1>/dev/null ; then
        mkdir -p "$(dirname "$fullfilename")"
        _run_dar -c "$fullfilename" -g "$dir"

    else
    # Otherwise, run an incremental backup against a full backup
        incrfilename="$( _generate_dar_incr_backup_filename "$dir_basename" )"
        mkdir -p "$(dirname "$fullfilename")"
        mkdir -p "$(dirname "$incrfilename")"
        _run_dar -c "$incrfilename" -g "$dir" -A "$fullfilename"
    fi
}

_generate_dar_full_backup_filename () {
    filename="$1"; shift
    echo "$BACKUP_DIR/$( date -u +%Y )/$filename"
}
_generate_dar_incr_backup_filename () {
    filename="$1"; shift
    echo "$BACKUP_DIR/$( date -u +%Y )/$( date -u +%m )/$filename.$( date --utc +%Y%m%d-%H%M%S )"
}

_main "$@"
