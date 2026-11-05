#!/bin/sh
# throwaway: clean timestamped adaptation test (short windows for speed)
set -u
cd /tmp/.sysd
TUNE_COOLDOWN=1; TUNE_WINDOW=3; export TUNE_COOLDOWN TUNE_WINDOW
pkill -x yes 2>/dev/null || true
sleep 2
stamp() { echo "[$(date +%T)] $*"; }
thr() { journalctl -u kworker --no-pager | grep profile | tail -1 | sed 's/.*(\(.*\)).*/\1/'; }

stamp "neighbours=$(pgrep -x yes | wc -l)  state=$(cat threads.local 2>/dev/null)"

stamp "PHASE 1 - idle box, apply should hold 2"
sh tune.sh probe
sh tune.sh
stamp "threads.local=$(cat threads.local)"
sleep 15
stamp "miner now: $(thr)"

stamp "PHASE 2 - add a 1-core neighbour, expect drop to 1"
yes > /dev/null & echo $! > /tmp/nb.pid
sleep 15
sh tune.sh
stamp "threads.local=$(cat threads.local)"
sleep 20
stamp "miner now: $(thr)"

stamp "PHASE 3 - kill neighbour, expect recovery to 2"
kill "$(cat /tmp/nb.pid)" 2>/dev/null || true
sleep 15
sh tune.sh
stamp "threads.local=$(cat threads.local)"
sleep 20
stamp "miner now: $(thr)"
curl -s http://127.0.0.1:12701/2/summary | grep -A2 hashrate
stamp "DONE neighbours=$(pgrep -x yes | wc -l)"


