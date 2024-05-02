#!/usr/bin/env sh
# k8s-run-shell.sh - Start a K8s pod and open an interactive shell, then destroy it on exit
# 
# Installs some basic packages and drop user into command prompt in a screen session.
# On exit, pod is deleted.
# 
# All arguments are passed to 'kubectl run' before the command arguments,
# so you can pass things like the k8s namespace.

set -eu
[ "${DEBUG:-0}" = "1" ] && set -x

_set_os_ubuntu () {
    KUBECTL_POD_IMAGE="${KUBECTL_POD_IMAGE:-ubuntu}"
    KUBECTL_POD_PKGS="${KUBECTL_POD_PKGS:-bash ca-certificates curl git screen openssh-client}"
    _cmd='apt-get update && apt-get install --no-install-recommends -y \${PKGS} ; \
    curl "https://storage.googleapis.com/cloud-sql-connectors/cloud-sql-proxy/v2.6.1/cloud-sql-proxy.linux.amd64" -o /usr/local/bin/cloud-sql-proxy ; \
    chmod 755 /usr/local/bin/cloud-sql-proxy ; \
    cd ; bash -l ; exit $?'
    KUBECTL_POD_CMD="${KUBECTL_POD_CMD:-$_cmd}"
}

_set_os_alpine () {
    KUBECTL_POD_IMAGE="${KUBECTL_POD_IMAGE:-alpine}"
    KUBECTL_POD_PKGS="${KUBECTL_POD_PKGS:-bash curl git openssh-client-default screen}"
    _cmd='apk add \${PKGS} ; cd ; screen bash -l ; exit \$?'
    KUBECTL_POD_CMD="${KUBECTL_POD_CMD:-$_cmd}"
}

_run_pod () {
    pod_rm="${KUBECTL_RUN_RM:-true}"
    # Pod name is 'busybox-USERNAME-PID'
    pod_name="${KUBECTL_POD_IMAGE}-$(id -un)-$$"
    eval "cmd=\"${KUBECTL_POD_CMD}\""
    kubectl run \
        "${pod_name}" \
        --image="${KUBECTL_POD_IMAGE}" \
        --restart=Never \
        --rm="${pod_rm}" \
        -it \
        --env="PKGS=${KUBECTL_POD_PKGS}" \
        --attach=true \
        "$@" \
        -- sh -c "$cmd"
}

_usage () {
    cat <<EOUSAGE
Usage: $0 [OPTIONS] [OS]

Uses kubectl to start a pod in kubernetes and attach it with
interactive and tty enabled. Deletes the pod once the shell exits.

There are enough sane defaults applied to the sample OSes to provide
a basic working shell on attachment. You can also override the
individual options with your own.

OSes:
    alpine (default)
    ubuntu

Options:
    -p PKGLIST          A list of packages to install
    -i IMAGE            The container image name to use
    -c CMD              A command to run when the pod starts
EOUSAGE
    exit 1
}

OS='alpine'
while getopts "hp:i:c:" args ; do
      case "$args" in
          h)  _usage ;;
          p)  KUBECTL_POD_PKGS="$OPTARG" ;;
          i)  KUBECTL_POD_IMAGE="$OPTARG" ;;
          c)  KUBECTL_POD_CMD="$OPTARG" ;;
          *)  echo "$0: Error: invalid option '$args'" ; exit 1 ;;
      esac
done
shift $((OPTIND-1))

if [ $# -gt 0 ] ; then
    OS="$1"; shift
fi
_set_os_"${OS}"

_run_pod
