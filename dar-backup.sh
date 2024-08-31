#!/usr/bin/env sh
# dar-backup.sh - generate a full and/or incremental backup using dar
set -eu
[ "${DEBUG:-0}" = "1" ] && set -x


BACKUP_DIR="$HOME/.Backup/"


_usage () {
        cat <<EOUSAGE
Usage: $0 [OPTIONS] FILE [..]

Make an incremental or full (if one doesn't exist yet) backup of a FILE (can be
a directory), using Dar. FILE must be a path relative to the current directory.

This script will create a backup directory ~/.Backup/ to store your backups in.
Backups are stored in a hierarchical file tree based on year and month.
The basename of DIR is the name of the backup file.

If no full backup has been taken this year, a full backup of DIR is taken.
Otherwise, an incremental backup is taken.

There is no limit on the number of backups, so the more you run this script,
the more incremental backups will pop up, but they will only be 24kB if nothing
has changed.

nice and ionice are used to lower the CPU and IO priorities as much as possible.

OPTIONS:
  -h                        This screen
  -n                        Dry-run mode
EOUSAGE
        exit 1
}

_main () {

    _run_usage=0 _dry_run=0
    while getopts "hn" arg ; do
        case "$arg" in
            h)          _run_usage=1 ;;
            n)          _dry_run=1 ;;
            *)          _die "Unknown argument '$arg'" ;;
        esac
    done
    shift $((OPTIND-1))

    if [ $# -lt 1 ] || [ "${_run_usage:-0}" = "1" ] ; then
        _usage
    fi

    ###########################################################

    [ -d "$BACKUP_DIR" ] || mkdir -p "$BACKUP_DIR"
    BACKUP_DIR="$(cd "$BACKUP_DIR" && pwd -P)"
    mkdir -p "$BACKUP_DIR"

    for file in "$@" ; do
        _run_dar_single "$file"
    done
}

# Run dar.
#   If dry-run mode enabled, only echo the command.
#   Use 'nice' and 'ionice' to lower cpu and io priority as much as possible.
#   Pass sane default options.
#   Pass any extra arguments in the middle of the command options, as the --alter=no-case option
#   alters all the following arguments.
_run_dar () {
    $(if [ "${_dry_run:-0}" = "1" ] ; then echo "echo" ; fi) \
        nice -n 19 ionice -c 3 -t \
            dar \
                --no-overwrite \
                -Q \
                --quiet \
                --hash sha1 \
                "$@" \
                --compression=zstd \
                --alter="no-case" \
                -Z "*.gz" -Z "*.tgz" -Z "*.bz2" -Z "*.tbz2" -Z "*.xz" -Z "*.txz" -Z "*.zip" -Z "*.png" -Z "*.jpg" -Z "*.jpeg" -Z "*.avi" -Z "*.mpg" -Z "*.mpeg" -Z "*.mp3"
}

_run_dar_single () {
    file="$1"; shift

    if [ ! -f "$file" ] && [ ! -d "$file" ] ; then
        _log "ERROR: File '$file' is not a file or directory, cannot run backup"
        _usage
    fi

    fullfilename="$( _generate_dar_full_backup_filename "$file" )"

    # If no matching 'full backup' is found, run a full backup
    if ! ls "$fullfilename."*.dar 2>/dev/null 1>/dev/null ; then

        mkdir -p "$(dirname "$fullfilename")"
        _run_dar -c "$fullfilename" -g "$file"

    else
    # Otherwise run an incremental backup
        incrfilename="$( _generate_dar_incr_backup_filename "$file" )"
        lastincrfilename="$( _lookup_last_dar_incr_backup_filename "$file" )"

        mkdir -p "$(dirname "$fullfilename")" "$(dirname "$incrfilename")"
        _run_dar -c "$incrfilename" -g "$file" -A "$lastincrfilename"
        _remove_empty_archive "$incrfilename"
    fi
}

_generate_dar_full_backup_filename () {
    filepath="$1" ; filename="$(basename "$filepath")" ; shift
    shastub="$( printf "%s\n" "$(pwd)/$filepath" | sha256sum | cut -c 1-8 )"

    printf "%s\n" \
        "$BACKUP_DIR/$( date -u +%Y )/$filename.$shastub"
}

_generate_dar_incr_backup_filename () {
    filepath="$1" ; filename="$(basename "$filepath")" ; shift
    shastub="$( printf "%s\n" "$(pwd)/$filepath" | sha256sum | cut -c 1-8 )"

    printf "%s\n" \
        "$BACKUP_DIR/$( date -u +%Y )/$( date -u +%m )/$filename.$shastub.$( date --utc +%Y%m%d-%H%M%S )"
}

_lookup_last_dar_incr_backup_filename () {
    filepath="$1" ; filename="$(basename "$filepath")" ; shift
    shastub="$( printf "%s\n" "$(pwd)/$filepath" | sha256sum | cut -c 1-8 )"

    curyear="$( date -u +%Y )"
    lastyear="$( date -u +%Y)"
    curmonth="$( date -u +%m )"
    lastmonth="0$((${curmonth##0}-1))"
    # Set last year/month for archive file search
    if [ "$curmonth" = "01" ] ; then
        lastmonth="12"
        lastyear="$((curyear-1))"
    fi

    # Look for the last incremental backup in a couple of places, due to year/month rollover
    lastincrfile='' lastincrfilearchive=''
    for incrpath in  "$curyear/$curmonth"  "$lastyear/$lastmonth" ; do

        # Use file globbing to list .dar archives matching the path, filename, and SHA stub,
        # sorting the result (which should work by date) and return the last file found.
        lastincrfile="$( ls "$BACKUP_DIR/$incrpath/$filename.$shastub".*.dar 2>/dev/null | sort | tail -1 )"
        lastincrfilearchive="${lastincrfile%.[0-9]*.dar}"
        if [ -e "$lastincrfile" ] ; then
            break
        fi

    done

    # If there was no previous incremental backup, then we need to start with the full backup
    # as the first incremental backup point (as this will now be the first incremental backup)
    if [ -z "$lastincrfile" ] ; then
        _generate_dar_full_backup_filename "$filepath"
    else
        printf "%s\n" "$lastincrfilearchive"
    fi
}

_remove_empty_archive () {
    filepath="$1" ; filename="$(basename "$filepath")" ; shift
    dirpath="$(dirname "$filepath")"
    archive="${filename%.[0-9]*.dar}"
    
    # Check if the archive backed up any files
    if [ ! "${_dry_run:-0}" = "1" ] ; then
        changed="$(dar -l "$dirpath/$archive" -as | tail -n +3 | wc -l)"

        if [ "$changed" -lt 1 ] ; then
            _log "Archive '$dirpath/$archive' had no saved files; deleting archive to save space"
            rm -f "$dirpath/$archive".*.dar "$dirpath/$archive".*.dar.sha1
        fi
    fi
}

_log () { printf "$0: %s\n" "$*" ; }


_main "$@"
