#!/usr/bin/env sh
# Run Alpine Linux in Kubernetes.
# Installs some basic packages and drop user into command prompt in a screen session.
# On exit, pod is deleted.
# 
# All arguments are passed to 'kubectl run' before the command arguments,
# so you can pass things like the k8s namespace.
set -eu
[ "${DEBUG:-0}" = "1" ] && set -x

# Pod name is 'busybox-USERNAME-PID'
kubectl run \
    "alpine-$(id -un)-$$" \
    --image=alpine \
    --restart=Never \
    --rm=true \
    -it \
    --env="PKGS=bash curl git openssh-client-default screen" \
    --attach=true \
    "$@" \
    -- sh -c 'apk add $PKGS ; cd ; screen bash -l ; exit $?'
