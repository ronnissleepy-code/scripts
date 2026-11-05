#!/bin/sh
# throwaway: of the addresses where :2375 answers AT ALL, how many are docker?
# (if "answered" is also ~0 then the rarity is real, not a detection bug)
PAR=${PAR:-64}
OUT=/tmp/conn.any
: > "$OUT"
cat > /tmp/conn.one <<'EOF'
ip=$1
r=$(curl -sS -m 2 --connect-timeout 2 "http://$ip:2375/version" 2>/dev/null) || r=""
[ -n "$r" ] || exit 0
case "$r" in
    *ApiVersion*) kind=docker ;;
    *)            kind=other ;;
esac
printf '%s\t%s\t%s\n' "$ip" "$kind" "$(printf '%s' "$r" | head -c 40 | tr -d '\n')" >> /tmp/conn.any
EOF
for net in "$@"; do
  h=1
  while [ "$h" -lt 255 ]; do printf '%s.%s\n' "$net" "$h"; h=$((h + 1)); done
done > /tmp/conn.ips
n=$(wc -l < /tmp/conn.ips)
xargs -P "$PAR" -n 1 sh /tmp/conn.one < /tmp/conn.ips
echo "probed $n addresses on 2375; answered=$(wc -l < "$OUT")"
cat "$OUT"
