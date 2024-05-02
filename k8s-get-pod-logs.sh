#!/usr/bin/env sh
# k8s-get-pod-logs.sh - Save any Crashing, Error, or Failed pods' logs to a file

#set -eu
[ "${DEBUG:-0}" = "1" ] && set -x

mkdir -p pods

kubectl get pods | while read -r line ; do
    pod_name="$(echo "$line" | awk '{print $1}')"
    echo "Found pod '$pod_name'"
    if echo "$line" | grep -E 'CrashLoopBackOff|Error|Failed' ; then
        echo "  Pod has errors; dumping logs"
        kubectl logs "$pod_name" > pods/"$pod_name".log &
    fi
done
