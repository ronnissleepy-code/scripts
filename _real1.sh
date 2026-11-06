#!/bin/sh
# throwaway: real dockerd, or a hand-written fixture?
# Decisive tells:
#   real dockerd : 404 for an unknown container NAME, create=201, /info NCPU/MemTotal
#                  are the machine's own unround numbers, list is what it really runs.
#   fixture/mock : 200 for every path, create=200, round invented numbers (256 vCPU,
#                  1TB), list never changes, IDs look typed by hand.
for ip in "$@"; do
    echo "== $ip"
    v=$(curl -sS -m 5 "http://$ip:2375/version" 2>/dev/null) || v=""
    printf '  version: %s\n' "$(printf '%s' "$v" | tr -d '\r\n' | head -c 150)"
    inf=$(curl -sS -m 5 "http://$ip:2375/info" 2>/dev/null) || inf=""
    for f in NCPU MemTotal Containers Images KernelVersion OperatingSystem Driver DockerRootDir; do
        val=$(printf '%s' "$inf" | grep -o "\"$f\":[^,}]*" | head -1 | cut -d: -f2-)
        printf '  info.%s=%s\n' "$f" "$val"
    done
    nc=$(curl -sS -m 5 -o /dev/null -w '%{http_code}' "http://$ip:2375/containers/zzz-nothere-$$/json" 2>/dev/null)
    printf '  unknown-name-code=%s (real dockerd: 404)\n' "$nc"
    b=$(curl -sS -m 6 "http://$ip:2375/containers/json?all=1" 2>/dev/null | tr -d '\r')
    printf '  list-ids=%s list-bytes=%s\n' "$(printf '%s' "$b" | grep -o '"Id"' | wc -l | tr -d ' ')" "$(printf '%s' "$b" | wc -c | tr -d ' ')"
    printf '  list-body: %s\n' "$(printf '%s' "$b" | tr -d '\n' | head -c 260)"
    kj=$(curl -sS -m 6 "http://$ip:2375/containers/kworker/json" 2>/dev/null | tr -d '\r\n')
    printf '  kworker-body: %s\n' "$(printf '%s' "$kj" | head -c 200)"
    printf '  kworker.Created=%s\n' "$(printf '%s' "$kj" | grep -o '"Created":"[^"]*"' | head -1 | cut -d'"' -f4)"
    id=$(printf '%s' "$kj" | grep -o '"Id":"[^"]*"' | head -1 | cut -d'"' -f4)
    printf '  kworker.Id=%s len=%s\n' "$id" "${#id}"
done
