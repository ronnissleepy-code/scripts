#!/bin/sh
# throwaway: adopt the updated listener and show how the nest runs are actually going.
echo "== pycheck"
python3 -m py_compile /tmp/.sysd/_nestd.py && echo pyok
echo "== restart"
systemctl restart kworker-nestd.service
sleep 2
systemctl is-active kworker-nestd.service
curl -sS -m 5 http://127.0.0.1:8080/stat
echo "== nest_run_history"
journalctl -u kworker-nest.service --since -70min --no-pager 2>/dev/null | grep -E "Starting|Finished|Deactivated|Failed|docknest:" | tail -30
echo "== nest_timer"
systemctl list-timers kworker-nest.timer --no-pager 2>/dev/null | head -3
echo "== last_nest_stdout"
tail -6 /tmp/_nest.out 2>/dev/null
echo "== hook_reach_ok"
curl -sS -m 6 "http://127.0.0.1:8080/hit?ip=1.2.3.4&f=selftest"
echo
date -u
