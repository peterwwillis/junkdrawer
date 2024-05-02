#!/usr/bin/env sh
# apt-update-security-packages.sh - Update Apt packages for security updates

_find_procs_deleted_deps () {
    ps xh -o pid |
    while read PROCID; do
           grep 'so.* (deleted)$' /proc/$PROCID/maps 2> /dev/null
           if [ $? -eq 0 ]; then
                   CMDLINE=$(sed -e 's/\x00/ /g' < /proc/$PROCID/cmdline)
                   echo -e "\tPID $PROCID $CMDLINE\n"
           fi
    done
}

sudo apt-get update
apt-get -s dist-upgrade |grep "^Inst" |grep -i securi 

# sudo unattended-upgrade --dry-run -d
sudo apt-get -s dist-upgrade | grep "^Inst" | 
    grep -i securi | awk -F " " {'print $2'} | 
        xargs sudo apt-get install

sudo checkrestart -v || true
_find_procs_deleted_deps
