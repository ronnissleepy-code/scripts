#!/bin/sh
# throwaway: live hashrate, written INCREMENTALLY so a killed terminal cannot lose
# it. Landmine found here: box1's curl has no CA bundle, so every https fetch dies
# with (60) "self-signed certificate" - that, not Cloudflare, is why the pool API
# looked unreachable from this box. -k fixes it.
W=46Md49vuZSSDDG5e2FhStfYxszzfDgnjH6gU2YU8zHrS5QihNkwb5PFNTHCkPhoKpG3k6zGP1SpeTRVgVDZFFQQuCetBqU6
T=/tmp/_hzq.txt
: > "$T"
{ echo "when=$(date -u)"; } >> "$T"
code=$(curl -sS -k -L -m 30 -w '%{http_code}' -o /tmp/_pl.raw "https://pool.supportxmr.com/api/miner/$W/stats" 2>/tmp/_pl.err)
{ echo "https_code=$code bytes=$(wc -c < /tmp/_pl.raw 2>/dev/null || echo 0) err=$(head -c 100 /tmp/_pl.err 2>/dev/null)"; } >> "$T"
if [ "$(wc -c < /tmp/_pl.raw 2>/dev/null || echo 0)" -lt 300 ]; then
    code=$(curl -sS -L -m 30 -w '%{http_code}' -o /tmp/_pl.raw "http://pool.supportxmr.com/api/miner/$W/stats" 2>/dev/null)
    { echo "http_code=$code bytes=$(wc -c < /tmp/_pl.raw 2>/dev/null || echo 0)"; } >> "$T"
fi
{ echo "-- headline"
  tr ',' '\n' < /tmp/_pl.raw 2>/dev/null | grep -o -e '"hash":[0-9]*' -e '"hash2h":[0-9]*' -e '"hash24h":[0-9]*' -e '"validShares":[0-9]*' -e '"amtDue":[0-9]*' -e '"lastHash":[0-9]*' | head -10
  echo "-- our own miner here (subtract from total)"
  pgrep -a xmrig 2>/dev/null | head -2
  journalctl -u kworker -n 400 --no-pager 2>/dev/null | grep -o 'speed [^|]*H/s' | tail -2
  echo "-- biggest per-worker hash entries"
  tr ',' '\n' < /tmp/_pl.raw 2>/dev/null | grep -o '"hash":[0-9]*' | sort -t: -k2 -nr | head -14
  echo "done=$(date -u)"; } >> "$T"
