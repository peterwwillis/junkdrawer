#!/usr/bin/env sh
# setup-hibernate-ubuntu.sh - Set up hibernation mode in Ubuntu
#
set -u
[ "${DEBUG:-0}" = "1" ] && set -x

_info () { printf "Info: %s\n" "$*" ; }
_exit () { printf "Info: %s\n" "$*" ; exit 0 ; }
_die () { printf "ERROR: %s\n" "$*" 1>&2 ; exit 1 ; }

_modify_grub () {

    firstswap="$(tail -n +2 /proc/swaps | awk '{print $1}' | head -1)"

    blk_info="$(sudo blkid -o export "$(df "$firstswap" | tail -1 | awk '{print $1}')" )"

    [ -n "$blk_info" ] || _die "No blkid info for swap '$firstswap'"

    eval "$blk_info"

    file_offset="$(sudo filefrag -v "$firstswap" | grep -E "^[[:space:]]+0:[[:space:]]" | awk '{print $4}' | sed -E 's/\.//g' )"

    grub_line="$( grep -E "^[[:space:]]*GRUB_CMDLINE_LINUX_DEFAULT" /etc/default/grub )"

    [ -n "$grub_line" ] || _die "Could not detect grub default cmdline"

    eval "$grub_line"

    _info "This is your current Grub default options: '$GRUB_CMDLINE_LINUX_DEFAULT'"

    #new_grubline="GRUB_CMDLINE_LINUX_DEFAULT=\"$GRUB_CMDLINE_LINUX_DEFAULT resume=UUID=${UUID} resume_offset=${file_offset}\""
    new_grubline="$GRUB_CMDLINE_LINUX_DEFAULT resume=UUID=${UUID} resume_offset=${file_offset}"


    _info "I will now overwrite it with: '$new_grubline'"
    read -p "Proceed? [y/N]" QUESTION
    if [ ! "$QUESTION" = "y" -a ! "$QUESTION" = "Y" ] ; then
        _die "Quitting early."
    fi

    sudo sed -i -E "s/^[[:space:]]*GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT=\"$new_grubline\"/" /etc/default/grub

    _info "Done modifying grub config."
}

_install_tools () {

    _info "Installing pm-utils ..."
    echo ""
    sudo apt install pm-utils || _die "Error returned while trying to install pm-utils. Exiting."
    echo ""
}

_update_boot () {
    _info "Updating initrd ..."
    echo "RESUME=UUID=${UUID} resume_offset=${file_offset}" | sudo tee /etc/initramfs-tools/conf.d/resume
    sudo update-initramfs -c -k all

    _info "Updating grub ..."
    echo ""
    sudo update-grub
}

_enable_hibernate_polkit () {
    polkit_content='
[Re-enable hibernate by default in upower]
Identity=unix-user:*
Action=org.freedesktop.upower.hibernate
ResultActive=yes

[Re-enable hibernate by default in logind]
Identity=unix-user:*
Action=org.freedesktop.login1.hibernate;org.freedesktop.login1.handle-hibernate-key;org.freedesktop.login1;org.freedesktop.login1.hibernate-multiple-sessions;org.freedesktop.login1.hibernate-ignore-inhibit
ResultActive=yes
'
    echo "$polkit_content" | sudo tee /etc/polkit-1/localauthority/50-local.d/org.freedesktop.enable-hibernate.pkla

}

_check_hibernate () {
    systemd_state="$(sudo systemctl hibernate 2>&1)"
    if printf "%s\n" "$systemd_state" | grep -q 'is not configured' ; then
        _info "Systemd does not have hibernate set up yet. Continuing."
    else
        _die "Systemd seems to think hibernate is working? Exiting."
    fi

    state_state="$(cat /sys/power/state)"
    if [ "$state_state" = "freeze mem disk" ] ; then
        _exit "Hibernate appears to be available? Exiting."
    else
        _info "Hibernate does not appear to be working yet. Continuing."
    fi
    echo ""

    if [ "$(cat /sys/power/disk)" = "[disabled]" ] || \
       sudo dmesg | grep -E "hibernation is restricted; see man kernel_lockdown.7" \
    then
        echo ""
        _info "Unfortunately, you will not be able to use hibernate, due to kernel lockdown mode."
        _info "This is enabled by default if you use EFI Secure Boot mode."
        _info "Disable Secure Boot and try again."
        exit 1
    fi
}

_check_hibernate
_install_tools
_modify_grub
_update_boot

