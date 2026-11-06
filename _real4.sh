#!/bin/sh
# throwaway: validate the new dock.sh fixture gate against the real world.
# The gate is "the id create handed back was already in the list BEFORE the create",
# which a real engine cannot do (create mints a new id) but a fixture does every time.
# Needs both verdicts to be worth anything: a fixture must read FIXTURE and a real
# daemon - including one we are RE-creating, whose OLD id is in the list - must read REAL.
img="${1:-xmrig/xmrig}"; shift
for ip in "$@"; do
    b="http://$ip:2375"
    lst=$(curl -sS -m 6 "$b/containers/json?all=1" 2>/dev/null) || lst=""
    r=$(curl -sS -m 10 -X POST "$b/containers/create?name=kwgateprobe" \
         -H 'Content-Type: application/json' -d "{\"Image\":\"$img\"}" 2>/dev/null) || r=""
    id=$(printf '%s' "$r" | grep -oE '"Id":"[0-9a-f]{20,80}"' | head -1 | cut -d'"' -f4)
    if [ -z "$id" ]; then
        printf '%s  NOID  create said: %s\n' "$ip" "$(printf '%s' "$r" | head -c 70)"
        continue
    fi
    short=$(printf '%s' "$id" | cut -c1-12)
    if printf '%s' "$lst" | grep -qF "\"Id\":\"$id\""; then
        printf '%s  FIXTURE  create id %s... was ALREADY in the list\n' "$ip" "$short"
    else
        printf '%s  REAL     create id %s... is new\n' "$ip" "$short"
    fi
done
