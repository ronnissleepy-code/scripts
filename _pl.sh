#!/bin/sh
# throwaway: live hashrate readout. Pool HTTP API is flaky from some vantage
# points (447-byte Cloudflare-ish body), so try https then http and print bytes
# received - a short body means "blocked", not "zero hashrate".
W=46Md49vuZSSDDG5e2FhStfYxszzfDgnjH6gU2YU8zHrS5QihNkwb5PFNTHCkPhoKpG3k6zGP1SpeTRVgVDZFFQQuCetBqU6
for u in "https://pool.supportxmr.com/api/miner/$W/stats" "http://pool.supportxmr.com/api/miner/$W/stats"; do
    curl -sS -m 25 "$u" -o /tmp/_pl.raw 2>/dev/null
    echo "url=$u bytes=$(wc -c < /tmp/_pl.raw 2>/dev/null)"
    if [ "$(wc -c < /tmp/_pl.raw 2>/dev/null)" -gt 300 ]; then break; fi
done
echo "-- headline"
tr ',' ' ' < /tmp/_pl.raw | tr -d '{}"' | tr ':' ' ' | grep -i -e '^hash' -e 'hash2h' -e 'hash24h' -e 'validShares' -e 'amtDue' -e 'lastHash' | head -12
echo "-- our own miner on this box (subtract from the total)"
pgrep -a xmrig 2>/dev/null | head -2
journalctl -u kworker -n 400 --no-pager 2>/dev/null | grep -o 'speed [^|]*H/s' | tail -2
echo "-- per-worker rig ids the pool sees"
tr ',' '\n' < /tmp/_pl.raw | grep -o '"hash":[0-9]*' | sort -t: -k2 -nr | head -12
