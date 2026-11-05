#!/bin/sh
# throwaway: which keyless BGP source answers with prefixes we can parse?
for u in 'https://api.bgpview.io/asn/24940/prefixes' \
         'https://stat.ripe.net/data/announced-prefixes/data.json?resource=AS24940'; do
    echo "== $u"
    curl -sS -m 12 -o /tmp/b.json -w 'http=%{http_code} bytes=%{size_download}\n' "$u" 2>&1
    echo "count_v4=$(grep -oE '"prefix": *"[0-9.]+/[0-9]+"' /tmp/b.json | wc -l)"
    grep -oE '"prefix": *"[0-9.]+/[0-9]+"' /tmp/b.json | head -3
    echo "head: $(head -c 120 /tmp/b.json)"
    echo
done
