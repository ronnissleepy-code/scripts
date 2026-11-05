#!/bin/sh
# ground truth on the hosts we just deployed to: do our containers exist, with what settings?
exec > /tmp/_diag4.out 2>&1
hosts=$(journalctl -u kworker-dock --since -30min --no-pager 2>/dev/null \
        | grep 'DEPLOYED kworker ->' | sed 's/.*-> //; s/ .*//' | sort -u | tail -6)
echo "probe_ts=$(date -u)"
echo "hosts=[$hosts]"
for ip in $hosts; do
    v=$(curl -sS -m 5 "http://$ip:2375/version")
    a=$(printf '%s' "$v" | grep -o '"ApiVersion": *"[0-9.]*"' | head -1 | cut -d'"' -f4)
    echo "== $ip api=${a:--}"
    if [ -n "$a" ]; then u="http://$ip:2375/v$a"; else u="http://$ip:2375"; fi
    n=$(curl -sS -m 6 "$u/containers/json?all=1" 2>/dev/null | grep -o '"/[A-Za-z0-9_.-]*"' | tr '\n' ' ')
    echo "names: $n"
    curl -sS -m 6 "$u/containers/kworker/json" 2>/dev/null \
        | grep -o -e '"CpuShares": *[0-9]*' -e '"Status":"[a-z]*"' -e 'cpu-max-threads-hint' | head -3
done
echo "done=$(date -u)"
