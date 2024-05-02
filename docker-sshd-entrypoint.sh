#!/usr/bin/env sh
# docker-sshd-entrypoint.sh - Install and run sshd in a Docker container
SSHDPORT="2222"

# Install sshd if it wasn't before. Try to use sudo if we're not root.
[ -n "${USER:-}" ] || USER=`id -un`
[ ! "$USER" = "root" ] && SUDO=sudo
if [ ! -x /usr/sbin/sshd ] ; then
    command -v apk     && $SUDO apk add --update --no-cache openssh-server # Alpine
    command -v apt-get && $SUDO apt-get update && $SUDO apt-get install openssh-server # Debian
    command -v yum     && $SUDO yum -y install openssh-server # CentOS
fi

# Don't mess with the .ssh folder too much in case the user wants to volume-mount
# their own .ssh folder into the container. If they don't volume-mount in the
# $HOME/.ssh_key.pub file, .ssh will be left alone.
mkdir -p .ssh
[ -r $HOME/.ssh_key.pub ] && cat $HOME/.ssh_key.pub >> .ssh/authorized_keys
mkdir -p .sshd/etc/ssh
ssh-keygen -A -f .sshd # generate new SSH host keys

# Compose the sshd_config file
cd .sshd ; CWD=`pwd`
printf "Port $SSHDPORT\nPasswordAuthentication no\nPermitUserEnvironment yes\n" > sshd_config
for i in `ls etc/ssh/ssh_host_* | grep -v pub` ; do
    echo "HostKey $CWD/$i" >> sshd_config
done

# Fix this user's login shell if it's currently set to nologin
[ -n "$USER" ] && ( getent passwd "$USER" | grep nologin ) && $SUDO usermod -s /bin/sh "$USER"

/usr/sbin/sshd -D -e -f sshd_config
