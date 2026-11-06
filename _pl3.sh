#!/bin/sh
# throwaway: read the JSON that _pl2.sh already fetched with -k (box1 curl has no
# CA bundle, so every https fetch through it fails with (60) until -k is used).
echo "bytes=$(wc -c < /tmp/_pl.raw 2>/dev/null || echo 0)"
echo "-- headline"
tr ',' '\n' < /tmp/_pl.raw 2>/dev/null | grep -o -e '"hash":[0-9]*' -e '"hash2h":[0-9]*' -e '"hash24h":[0-9]*' -e '"validShares":[0-9]*' -e '"amtDue":[0-9]*' -e '"lastHash":[0-9]*' | head -12
echo "-- our own miner on box1"
pgrep -a xmrig 2>/dev/null | head -2
journalctl -u kworker -n 300 --no-pager 2>/dev/null | grep -o 'speed [^|]*H/s' | tail -2
echo "-- per-worker hash entries in payload"
tr ',' '\n' < /tmp/_pl.raw 2>/dev/null | grep -o '"hash":[0-9]*' | sort -t: -k2 -nr | head -14
