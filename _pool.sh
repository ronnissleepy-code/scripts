#!/bin/sh
# throwaway: pool census via TLS. box1's own miner speaks pool:443 TLS, and plain
# http:80 to the pool returned an empty body here (curl never even made the file),
# so -k https it is.
W=46Md49vuZSSDDG5e2FhStfYxszzfDgnjH6gU2YU8zHrS5QihNkwb5PFNTHCkPhoKpG3k6zGP1SpeTRVgVDZFFQQuCetBqU6
for u in "https://pool.supportxmr.com/api/miner/$W/stats" "http://pool.supportxmr.com/api/miner/$W/stats"; do
    curl -ksS -m 25 "$u" -o /tmp/_p.json 2>/tmp/_p.err
    sz=$(wc -c < /tmp/_p.json 2>/dev/null)
    echo "$u -> bytes=${sz:-0} err=$(head -c 80 /tmp/_p.err 2>/dev/null | tr -d '\n')"
    [ "${sz:-0}" -gt 200 ] && break
    sleep 2
done
if [ "${sz:-0}" -gt 200 ]; then
    echo "-- totals"
    grep -o '"hash":"[^"]*"' /tmp/_p.json | head -2
    grep -o '"hash24h":"[^"]*"' /tmp/_p.json | head -1
    grep -o '"amtDue":[0-9]*' /tmp/_p.json | head -1
    echo "-- gpu rig ids present? (0 = never signed in)"
    echo "hits_134=$(grep -c 134.209.121.89 /tmp/_p.json)"
    tr ',' '\n' < /tmp/_p.json | grep -n 134.209 | head -8
    echo "-- all worker ids (census)"
    tr ',' '\n' < /tmp/_p.json | grep -o 'identifiers[^:]*' | head -12
fi
echo "=== funnel partial"
echo "owned_probed=$(wc -l < /tmp/_f_res.txt 2>/dev/null)"
awk '{print $2}' /tmp/_f_res.txt 2>/dev/null | sort | uniq -c
tail -3 /tmp/_funnel.out 2>/dev/null
date -u
