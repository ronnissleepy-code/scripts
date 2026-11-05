#!/bin/sh
# throwaway: measure exposed-docker density on sample /24s (usage: sh _mass.sh 5.9.100 64.227.10 ...)
PAR=${PAR:-64}
OUT=/tmp/mass.hits
: > "$OUT"
cat > /tmp/mass.one <<'EOF'
ip=$1
r=$(curl -fsS -m 2 --connect-timeout 2 "http://$ip:2375/version" 2>/dev/null) || exit 0
v=$(printf '%s' "$r" | grep -o '"Version":"[^"]*"' | head -1 | cut -d'"' -f4)
[ -n "$v" ] && echo "$ip docker=$v" >> /tmp/mass.hits
EOF
t0=$(date +%s)
for net in "$@"; do
  for h in $(seq 1 254); do
    printf '%s.%s\n' "$net" "$h"
  done
done > /tmp/mass.ips
n=$(wc -l < /tmp/mass.ips)
xargs -P "$PAR" -n 1 sh /tmp/mass.one < /tmp/mass.ips
t1=$(date +%s)
echo "scanned $n ips in $((t1-t0))s ; port2375-open daemons: $(wc -l < "$OUT")"
cat "$OUT"
