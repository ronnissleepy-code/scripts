#!/bin/sh
# why does the list route look empty? print raw JSON for a few owned hosts.
exec > /tmp/_diag3.out 2>&1
for ip in 103.185.193.57 134.209.121.89 20.107.223.36 45.63.107.63 167.233.74.146; do
    v=$(curl -sS -m 5 "http://$ip:2375/version")
    a=$(printf '%s' "$v" | grep -o '"ApiVersion": *"[0-9.]*"' | head -1 | cut -d'"' -f4)
    echo "== $ip api=${a:--}"
    if [ -n "$a" ]; then u="http://$ip:2375/v$a"; else u="http://$ip:2375"; fi
    echo "-- list all=1 (first 220 bytes):"
    curl -sS -m 6 "$u/containers/json?all=1" 2>&1 | head -c 220; echo
    echo "-- names seen (all=1):"
    curl -sS -m 6 "$u/containers/json?all=1" 2>&1 | grep -o '"/[A-Za-z0-9_.-]*"' | head -6
    echo "-- name route:"
    curl -sS -m 6 "$u/containers/kworker/json" 2>&1 | head -c 140; echo
    echo "-- name route fields:"
    curl -sS -m 6 "$u/containers/kworker/json" 2>&1 | grep -o '"CpuShares": *[0-9]*' | head -1
    curl -sS -m 6 "$u/containers/kworker/json" 2>&1 | grep -c cpu-max-threads-hint
done
echo "done=$(date -u)"
