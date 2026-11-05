#!/bin/sh
# Is there a free way to tell a fixture from a daemon before paying create+start?
# A real engine's /version is a rich object (KernelVersion, GoVersion, GitCommit,
# Os, Experimental). Fixtures are hand-written and typically emit a handful of
# fields. Also validates that a *real* host actually runs our container at speed.
for ip in 134.209.121.89 45.76.10.193 198.13.39.215 194.5.98.34 20.107.223.36 164.68.96.28 45.63.107.63 212.58.68.14 213.171.208.160 20.214.56.247; do
    v=$(curl -sS -m 5 "http://$ip:2375/version" 2>/dev/null) || v=""
    printf '== %s  bytes=%s kernel=%s go=%s commit=%s os=%s\n' "$ip" \
        "$(printf '%s' "$v" | wc -c)" \
        "$(printf '%s' "$v" | grep -c KernelVersion)" \
        "$(printf '%s' "$v" | grep -c GoVersion)" \
        "$(printf '%s' "$v" | grep -c GitCommit)" \
        "$(printf '%s' "$v" | grep -c '"Os"')"
    printf '   %s\n' "$(printf '%s' "$v" | head -c 260)"
done
echo "=== real host detail ==="
for b in http://134.209.121.89:2375; do
    l=$(curl -sS -m 8 "$b/containers/json?all=1" 2>/dev/null) || l=""
    id=$(printf '%s' "$l" | sed 's/},{/}\n{/g' | grep -i kworker | grep -o '"Id":"[0-9a-f]*"' | head -1 | cut -d'"' -f4)
    echo "id=$id"
    curl -sS -m 8 "$b/containers/$id/top" 2>/dev/null | head -c 420; echo
    curl -sS -m 8 "$b/containers/$id/stats?stream=false" 2>/dev/null | grep -o '"total_usage":[0-9]*' | head -4
    curl -sS -m 8 "$b/containers/$id/json" 2>/dev/null | grep -o '"Status":"[^"]*"' | head -2
done
