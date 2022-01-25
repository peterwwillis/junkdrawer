#!/bin/sh
# This script runs a detached Docker container with an entrypoint to run an sshd daemon.
set -eux

#CONTAINER_IMG=
CONTAINER_USER="deploy" # the user the container runs as
CONTAINER_HOME="/home/$CONTAINER_USER"
HOST_SSH_PORT="2222" # The port to export sshd to on localhost
PUBKEY="$HOME/.ssh/id_ed25519.pub"

# Before running this script, create an ssh key on the local host:
#       ssh-keygen -t ed25519 -N ''
#
# Set PUBKEY to the public key file created.
# Then run the sshd container below.
#
# This will volume-map the host's docker.sock,
# make a persistent Terraform plugin cache,
# a persistent volume for miscellaneous uses,
# the SSH public key created above (so we can login with it),
# maps in the entrypoint to set up and start sshd,
# and exports the sshd port to the local host.

docker run \
        --cap-add=SYS_PTRACE \
        --rm --detach \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v $HOME/.terraform.d/plugin-cache:$CONTAINER_HOME/.terraform.d/plugin-cache \
        -e TF_PLUGIN_CACHE_DIR="$CONTAINER_HOME/.terraform.d/plugin-cache" \
        -v sshd-persist:$CONTAINER_HOME/persist \
        -v $PUBKEY:$CONTAINER_HOME/.ssh_key.pub \
        -v `pwd`/sshd-entrypoint.sh:/sbin/sshd-entrypoint.sh \
        --entrypoint=/sbin/sshd-entrypoint.sh \
        -p 127.0.0.1:2222:$HOST_SSH_PORT \
        "$CONTAINER_IMG"

# Now you can login from the Docker host with the following:
#       ssh \
#        -v \
#        -o ForwardAgent=yes \
#        -o IdentitiesOnly=yes \
#        -i $PUBKEY \
#        -l $CONTAINER_USER \
#        -p $HOST_SSH_PORT \
#        127.0.0.1
#
# Or you can use the Docker host as a bastion for the container, with the following:
#       ssh \
#        -o ProxyCommand="ssh -o IdentitiesOnly=yes -i ~/.ssh/docker-host.pem -p 22 docker-host-user@docker-host-ip -N -W %h:%p" \
#        -i $PUBKEY \
#        -o IdentitiesOnly=yes \
#        -o ForwardAgent=yes \
#        -o CheckHostIP=no -o StrictHostKeyChecking=no \
#        -p $HOST_SSH_PORT \
#        -l $CONTAINER_USER \
#        127.0.0.1
#
# Note that with ForwardAgent=yes, your SSH keys have been forwarded into the container so you don't need to
# download them there.
#
# The CheckHostIP=no and StrictHostKeyChecking=no options are needed because the container's ssh host keys will
# change every time it starts. You may have to remove the previous host keys to get ForwardAgent to work again.
#
