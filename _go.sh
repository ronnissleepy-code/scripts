#!/bin/sh
# throwaway launcher: hard clean slate, then run exactly one test instance
pkill -f /tmp/tc.sh 2>/dev/null || true
pkill -f /tmp/t2.sh 2>/dev/null || true
pkill -x yes 2>/dev/null || true
sleep 2
nohup sh /tmp/tc.sh > /tmp/tc.log 2>&1 < /dev/null &
sleep 2
echo "LAUNCHED: $(pgrep -f /tmp/tc.sh | tr '\n' ' ')"
echo "stray yes: $(pgrep -x yes | wc -l)"

