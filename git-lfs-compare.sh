#!/usr/bin/env bash

set -eu
[ "${DEBUG:-0}" = "1" ] && set -x

declare -A lfsfilaa localfilaa
c_local_on_lfs=0
c_lfs_on_local=0

while read -r F ; do
    lfsfilaa["$F"]=1
done < <(git lfs ls-files -n)

for ext in $(cat .gitattributes | awk '{print $1}') ; do
    while read -r F ; do
        f="${F##./}"
        localfilaa["$f"]=1
    done < <(find . -type f -iname "$ext")
done

for f in "${!localfilaa[@]}" ; do
    if [ -n "${lfsfilaa["$f"]+1}" ] ; then
        echo "EXISTS:  Local on LFS: $f"
        c_local_on_lfs="$((c_local_on_lfs+1))"
    else
        echo "NOEXIST: Local on LFS: $f"
    fi
done

for f in "${!lfsfilaa[@]}" ; do
    if [ -n "${localfilaa["$f"]+1}" ] ; then
        echo "EXISTS:  LFS on Local: $f"
        c_lfs_on_local="$((c_lfs_on_local+1))"
    else
        echo "NOEXIST: LFS on Local: $f"
    fi
done

echo ""
echo "Locally matched files: ${#localfilaa[@]}"
echo "Local files that exist in LFS: $c_local_on_lfs"
echo "Local files not in LFS: $((${#localfilaa[@]}-$c_local_on_lfs))"
echo ""
echo "LFS files: ${#lfsfilaa[@]}"
echo "LFS files that exist locally: $c_lfs_on_local"
echo "LFS files don't exist locally: $((${#lfsfilaa[@]}-$c_lfs_on_local))"
