#!/usr/bin/env bash
# random-dict-password.sh - Generate a random password from dictionary words

set -eu
if [ "${1:-}" = "-h" -o "${1:-}" = "--help" ] ; then
    cat <<EOUSAGE
Usage: $0 [SEED]

Generates a "random" password based on dictionary words. If you pass a SEED,
the password is reproducible (assuming you use the same dictionary each time).
Otherwise the script will generate a random SEED each run using the OS's
/dev/urandom device.

The "algorithm" is just some random math operations I threw at a wall and
"looks random to me"; it's probably not secure.
EOUSAGE
    exit 1
fi

seed="$(cat /dev/urandom | LC_ALL=C tr -dc 'a-zA-Z0-9-_\$' | fold -w 20 | sed 1q)"

if [ $# -gt 0 ] ; then
    seed="$1"; shift
fi

minletter=5
maxletter=10
declare -a words=($(cat /usr/share/dict/words | grep -E "^[a-z]{$minletter,$maxletter}$" ))
[ "${DEBUG:-0}" = "1" ] && echo "total words: ${#words[@]}"
c=0 mt=0
# Look... I'm not good at math. This probably isn't secure.
for i in $(seq 0 $((${#seed}-1))) ; do
    n=$(($(printf "%d\n" "'${seed:$i:1}")-96))
    c=$((c+n))
    e=$((c**$i))
    m=$((e % ${#words[@]}))
    mt=$(( (mt+m) % ${#words[@]} ))
    mz=$(( (mt-m) % ${#words[@]} ))
    my=$(( (mz-e) % ${#words[@]} ))
    [ "${DEBUG:-0}" = "1" ] && echo "i $i letter ${seed:$i:1} n $n c $c e $e m $m mt $mt mz $mz my $my"
done
echo "${words[$m]} ${words[$mt]} ${words[$mz]} ${words[$my]}"
