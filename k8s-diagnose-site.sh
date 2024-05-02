#!/usr/bin/env sh
# k8s-diagnose-site.sh - Attempt to diagnose a web site in K8s

set -eu
[ "${DEBUG:-0}" = "1" ] && set -x

__err () { echo "$0: Error: $*" ; exit 1 ; }

if [ $# -lt 1 ]  ; then
    cat <<EOUSAGE
Usage: $0 URL
EOUSAGE
    exit 1
fi

url="$1"

host="$( echo "$url" | sed -E 's!^https?://([a-zA-Z0-9.-]+)[^a-zA-Z0-9.-]?.*!\1!g')"
urlpath="$( echo "$url" | sed -E 's!^https?://[a-zA-Z0-9.-]+!!' )"

ip="$(dig +short "$host")"

echo "url:     $url"
echo "urlpath: $urlpath"
echo "host:    $host"
echo "ip:      $ip"
echo ""

# Find the service that has this external IP
filter="{.items[?(@.status.loadBalancer.ingress[*].ip==\"$ip\")]}"
ingsvcjson="$(kubectl get -A services -o jsonpath="$filter")"

if [ -z "$ingsvcjson" ] ; then
    __err "Could not find service with IP '$ip'"
fi

# _jsfilter "JSON" "FIELD"
_jsfilter () { printf "%s\n" "$1" | jq -c -r "$2" ; }

ingsvcns="$( _jsfilter "$ingsvcjson" .metadata.namespace )"
ingsvcname="$( _jsfilter "$ingsvcjson" .metadata.name )"
ingsvcselector="$( _jsfilter "$ingsvcjson" .spec.selector | jq -j 'to_entries | .[] | "\(.key)=\(.value),"' | sed -e 's/,$//' )"
ingsvcdeploy="$( kubectl get -n "$ingsvcns" deployments --selector "$ingsvcselector" -o name )"
ingsvcpods="$( kubectl get -n "$ingsvcns" pods --selector "$ingsvcselector" -o name )"

echo "Service associated with IP:"
echo "   name:      $ingsvcname"
echo "   namespace: $ingsvcns"
echo "   selector:  $ingsvcselector"
echo "   deployment: $ingsvcdeploy"
echo "   pods: $ingsvcpods"

if [ -n "$ingsvcselector" ] ; then
    ingsvcpods="$( kubectl get pods --selector "$ingsvcselector" "--output=jsonpath={.items..metadata.name}" )"
    for i in $ingsvcpods ; do
        echo "      pod $i"
    done
fi

echo ""

# Find all ingresses whose rules have the hostname

echo "Ingresses matching host '$host' path '$urlpath' :"
ingressjson="$( kubectl get ingress -A -o "jsonpath={.items[?(@.spec.rules[*].host==\"$host\")]}" )"
printf "%s\n" "$ingressjson" | jq -M -c -r '{"name":.metadata.name,"namespace":.metadata.namespace,"paths":.spec.rules[].http.paths}' | \
    while read -r js ; do
        ingressname="$( _jsfilter "$js" .name )"
        ingressns="$( _jsfilter "$js" .namespace )"
        ingressbackendpathsjs="$( _jsfilter "$js" .paths )"

        #echo "ingressbackendpathsjs: $ingressbackendpathsjs"
        printf "%s\n" "$ingressbackendpathsjs" | jq -M -c -r '.[]  | {"path":.path,"name":.backend.service.name,"port":.backend.service.port.number}' | \
            while read -r pathjs ; do
                path="$( _jsfilter "$pathjs" .path )"
                svcname="$( _jsfilter "$pathjs" .name )"
                svcport="$( _jsfilter "$pathjs" .port )"
                if printf "%s\n" "$urlpath" | grep -q -E "^$path" ; then
                    printf "   namespace: %s\tname: %s\n" "$ingressns" "$ingressname"
                    printf "      path: %s\n           service: %s\n           port: %s\n" "$path" "$svcname" "$svcport"
                    # TODO: check for endpoints
                    # TODO: check for proper selector labels
                    svcjson="$(kubectl get -n "$ingressns" service "$svcname" -o json)"
                    svcselector="$( _jsfilter "$svcjson" .spec.selector | jq -j 'to_entries | .[] | "\(.key)=\(.value),"' | sed -e 's/,$//' )"
                    svcpods="$( kubectl get -n "$ingressns" pods --selector "$svcselector" -o name )"
                    printf "           pods: %s\n" "$svcpods"
                fi
            done

    done

