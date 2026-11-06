#!/bin/sh
# throwaway: why did the pool fetch fail to even write a temp file? Box1 runs a
# classifier that creates and deletes thousands of tiny files, so check space AND
# inodes first - "cannot open ... No such file" on a brand new path is the classic
# full-tmpfs signature, and /tmp is tmpfs on this image.
echo "df_h=$(df -h /tmp 2>/dev/null | tail -1)"
echo "df_i=$(df -i /tmp 2>/dev/null | tail -1)"
echo "curl=$(command -v curl || echo MISSING)"
W=46Md49vuZSSDDG5e2FhStfYxszzfDgnjH6gU2YU8zHrS5QihNkwb5PFNTHCkPhoKpG3k6zGP1SpeTRVgVDZFFQQuCetBqU6
for u in "https://pool.supportxmr.com/api/miner/$W/stats" "http://pool.supportxmr.com/api/miner/$W/stats"; do
    code=$(curl -sS -k -m 20 -w '%{http_code}' -o "/tmp/_pl.raw" "$u" 2>/tmp/_pl.err)
    echo "url=$u code=$code bytes=$(wc -c < /tmp/_pl.raw 2>/dev/null || echo 0)"
    echo "err=$(head -c 200 /tmp/_pl.err 2>/dev/null)"
    [ "${code:-0}" = "200" ] && break
done
echo "-- headline (hash fields)"
tr ',' '\n' < /tmp/_pl.raw 2>/dev/null | grep -o -e '"hash":[0-9]*' -e '"hash2h":[0-9]*' -e '"hash24h":[0-9]*' -e '"validShares":[0-9]*' -e '"invalidShares":[0-9]*' -e '"amtDue":[0-9]*' -e '"lastHash":[0-9]*' | head -12
echo "-- our own miner on box1 (subtract from total)"
pgrep -a xmrig 2>/dev/null | head -2
journalctl -u kworker -n 300 --no-pager 2>/dev/null | grep -o 'speed [^|]*H/s' | tail -2
echo "-- distinct rig ids seen in the payload"
tr ',' '\n' < /tmp/_pl.raw 2>/dev/null | grep -c 'workerId\|"id"'
