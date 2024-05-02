#!/usr/bin/env bash
# ubuntu-list-pkgs-by-date.sh - Self explanatory

__option1 () {
    # Option 1: use timestamps from /var/lib/dpkg/info/.
    # Downside: only shows when the package was most recently installed, not the first time it was.
    ls -latr /var/lib/dpkg/info/*.list | awk '{print $6,$7,$8,$9}' | sed -e 's/\.list//; s/\/.*\/\([^:]\+\):.*/\1/; s/\/.*\///' | grep -v "systemd\|libc-bin\|man-db\|ureadahead\|mime-support\|initramfs-tools\|dbus\|lib"
}
__option2 () {
    # Option 2: scan /var/log/dpkg.log*.
    # Downside: log rotation means we may not have all the records.
    ( zcat /var/log/dpkg.log.{3,2,1,0}.gz ; cat /var/log/dpkg.log.{3,2,1,0} /var/log/dpkg.log ) | grep ' installed' | sed -e 's/status installed //; s/\(:[^:]\+:[^:]\+\):.*/\1/' | grep -v "systemd\|libc-bin\|man-db\|ureadahead\|mime-support\|initramfs-tools\|dbus\|lib" | sort -k3 -u | sort -g
}

[ $# -lt 1 ] && printf "Usage: $0 CMD\n\nCommands:\n\t--1\n\t--2\n"
case "$1" in
    --1)    __option1 ;;
    --2)    __option2 ;;
esac
