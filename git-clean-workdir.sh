#!/bin/bash
[ "${DEBUG:-0}" = "1" ] && set -x

CWD="$(pwd)"
CWD_B="$(basedir "$CWD")"
BACKUP_DIR="../$CWD_B.bak"

# Make a backup directory
mkdir "$BACKUP_DIR"

# Clean up untracked files

git ls-files --others --exclude-standard | while read LINE ; do
    
    case "$LINE" in
        .terraform|*.log*|*.plan)
                                    rm -rf "$LINE" ;;
        *)
                                    cp -a --parents --backup=t "$LINE" "$BACKUP_DIR" ;
                                    rm -rf "$LINE" ;;
    esac
done

