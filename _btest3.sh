#!/bin/sh
# throwaway 3: does internetdb take several IPs per request (1/s x N), and does the
# shodan.io search page answer anyone? Both decide how big a keyless search can be.
sleep 5
echo "=== comma list of 3 ==="
curl -sS -m 15 "https://internetdb.shodan.io/1.1.1.1,8.8.8.8,9.9.9.9" -w " [http=%{http_code}]\n" | head -c 400
sleep 2
echo "=== single (control) ==="
curl -sS -m 15 "https://internetdb.shodan.io/8.8.8.8" -w " [http=%{http_code}]\n" | head -c 400
sleep 2
echo "=== comma list of 10 ==="
curl -sS -m 20 "https://internetdb.shodan.io/8.8.8.8,8.8.4.4,1.1.1.1,9.9.9.9,208.67.222.222,208.67.220.220,64.6.64.6,64.6.65.6,77.88.8.8,77.88.8.1" -w " [http=%{http_code}]\n" | head -c 400
sleep 2
echo "=== search page, no www, http1.1 ==="
curl -sS -m 20 --http1.1 -A "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36" \
     -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" \
     -H "Accept-Language: en-US,en;q=0.9" \
     "https://shodan.io/search?query=port%3A2375" -o /tmp/sh3.html \
     -w "http=%{http_code} bytes=%{size_download}\n"
grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' /tmp/sh3.html | sort -u | wc -l
head -c 300 /tmp/sh3.html
echo
echo "=== done ==="
