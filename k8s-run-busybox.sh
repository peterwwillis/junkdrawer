#!/usr/bin/env sh
# Run busybox in Kubernetes and drop user into command prompt. On exit, pod is deleted.
set -eu
[ "${DEBUG:-0}" = "1" ] && set -x

# Pod name is 'busybox-USERNAME-PID'
kubectl run "busybox-$(id -un)-$$" --image=busybox --restart=Never -it --attach=true --rm=true -- sh -l
