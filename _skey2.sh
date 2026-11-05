#!/bin/sh
# what can an OSS key actually do? host lookup (authoritative ports) vs search (membership-only)
K=XZgCF4veHn1Y8mTTBcUC4yP11B7XPALE
echo "== host lookup: box1 =="
curl -sS -m 20 "https://api.shodan.io/shodan/host/167.233.74.146?key=$K" -o /tmp/h1.json -w 'http=%{http_code} bytes=%{size_download}\n'
grep -oE '"(ports|org|isp|country_name)": *[^,}]+' /tmp/h1.json | head -6
echo "-- raw --"; head -c 260 /tmp/h1.json; echo
echo
echo "== host lookup: known :2375 daemon 64.227.10.5 =="
curl -sS -m 20 "https://api.shodan.io/shodan/host/64.227.10.5?key=$K" -o /tmp/h2.json -w 'http=%{http_code} bytes=%{size_download}\n'
grep -oE '"(ports|hostnames|org)": *[^,}]*' /tmp/h2.json | head -5
echo "-- raw --"; head -c 200 /tmp/h2.json; echo
echo
echo "== internetdb comma batch (3 IPs in ONE request) =="
curl -sS -m 15 "https://internetdb.shodan.io/1.1.1.1,8.8.8.8,64.227.10.5" -o /tmp/b3.json -w 'http=%{http_code} bytes=%{size_download}\n'
head -c 320 /tmp/b3.json; echo
echo
echo "== free: shodan/ports =="
curl -sS -m 15 "https://api.shodan.io/shodan/ports?key=$K" -o /tmp/p.json -w 'http=%{http_code} bytes=%{size_download}\n'
head -c 160 /tmp/p.json
