#!/bin/sh
# throwaway: reboot-survival audit
echo "== /tmp fstype =="
findmnt -no FSTYPE /tmp 2>/dev/null || echo "(not a separate mount)"
echo "== kworker unit files =="
ls /etc/systemd/system/ | grep -i -e kworker -e ghost
echo "== ExecStart lines =="
grep -h ExecStart /etc/systemd/system/*kworker* 2>/dev/null
echo "== enabled state =="
systemctl list-unit-files 2>/dev/null | grep -i kworker
echo "== cron =="
crontab -l 2>/dev/null
ls /etc/cron.d/ 2>/dev/null
echo "== anything referencing .sysd outside /etc/systemd =="
grep -rl 'sysd' /etc/rc.local /etc/profile.d/ /etc/systemd/system 2>/dev/null
