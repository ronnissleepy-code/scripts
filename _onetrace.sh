#!/bin/sh
# single-host traced run, filtered to what dock_one *does* (not the set -x noise)
sh -x /tmp/.sysd/dock.sh 167.233.74.146 > /tmp/_one.raw 2>&1
grep -v '^+' /tmp/_one.raw | head -40 > /tmp/_one.out
echo "=== box1 lines" >> /tmp/_one.out
grep -e 'dock: 167.233.74.146' /tmp/_one.raw | tail -8 >> /tmp/_one.out
echo "=== last 12 non-trace lines" >> /tmp/_one.out
grep -v '^+' /tmp/_one.raw | tail -12 >> /tmp/_one.out
echo DONE >> /tmp/_one.out
