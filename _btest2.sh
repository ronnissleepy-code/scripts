#!/bin/sh
# throwaway 2: (A) shodan.io search page with real browser headers + cookie jar
#             (B) internetdb lookups with CORRECT urls at -P1/4/8 -> the real rate
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"
echo "=== A: shodan.io search, browser headers + cookie jar ==="
curl -sS -m 25 -c /tmp/cj.txt -b /tmp/cj.txt --compressed \
  -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,*/*;q=0.8" \
  -H "Accept-Language: en-US,en;q=0.9" \
  -H "Upgrade-Insecure-Requests: 1" \
  -e "https://www.shodan.io/" -A "$UA" \
  "https://www.shodan.io/search?query=port%3A2375" -o /tmp/sh2.html \
  -w "http=%{http_code} bytes=%{size_download}\n"
echo "--- unique ips:"
grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' /tmp/sh2.html | sort -u | wc -l
grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' /tmp/sh2.html | sort -u | head -15
echo "--- markers:"
grep -oiE 'sign in|log in|no results|total sites|results|<title>[^<]*' /tmp/sh2.html | head -6
echo "--- size of title/body head:"
head -c 200 /tmp/sh2.html
echo
echo "=== B: internetdb rate at -P1/4/8 (20 lookups each) ==="
for p in 1 4 8; do
  t0=$(date +%s)
  for h in $(seq 1 20); do echo "https://internetdb.shodan.io/5.9.$h.$((p + 2))"; done \
    | xargs -P "$p" -n 1 curl -sS -m 10 -o /dev/null -w "%{http_code} " 2>/dev/null \
    | tr ' ' '\n' | sort | uniq -c | tr '\n' ' '
  t1=$(date +%s)
  echo " <- -P$p in $((t1 - t0))s"
  sleep 3
done
echo "=== done ==="
