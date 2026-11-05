#!/bin/sh
# throwaway: can we run a BIG keyless DB search?
#   A) scrape shodan.io search HTML for port:2375  (does it give us IPs?)
#   B) how much parallelism does internetdb tolerate -> how big can a sweep be?
echo "=== A: shodan.io search page, keyless ==="
curl -sS -m 25 -A "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36" \
     "https://www.shodan.io/search?query=port%3A2375" -o /tmp/sh.html \
     -w "http=%{http_code} bytes=%{size_download}\n" 2>&1
echo "--- unique IPs in the page:"
grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' /tmp/sh.html | sort -u | wc -l
grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' /tmp/sh.html | sort -u | head -12
echo "--- does it look like results or a login wall:"
grep -oiE 'sign in|log in|create account|results|total' /tmp/sh.html | sort | uniq -c | head

echo "=== B: internetdb throughput at -P 20 ==="
t0=$(date +%s)
for h in $(seq 1 40); do echo "5.9.$h.7"; done \
  | xargs -P 20 -n 1 curl -sS -m 8 -o /dev/null -w "%{http_code}\n" \
          https://internetdb.shodan.io/ 2>/dev/null \
  | sort | uniq -c
t1=$(date +%s)
echo "40 lookups at -P20 took $((t1 - t0))s"

echo "=== C: does the daemon port ever show up in internetdb ==="
for ip in 5.9.0.1 5.9.100.7 88.198.0.1 78.46.0.1; do
    printf '%s ' "$ip"
    curl -sS -m 8 "https://internetdb.shodan.io/$ip" 2>/dev/null | head -c 160
    echo
done
echo "=== done ==="
