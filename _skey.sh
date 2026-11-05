#!/bin/sh
# throwaway: validate the Shodan key, learn the plan limits, test a real :2375 search
K=XZgCF4veHn1Y8mTTBcUC4yP11B7XPALE
echo "== api-info (plan + credits) =="
curl -sS -m 15 "https://api.shodan.io/api-info?key=$K"
echo
echo "== search: port:2375 =="
curl -sS -m 25 "https://api.shodan.io/shodan/host/search?key=$K&query=port%3A2375" \
     -o /tmp/s2375.json -w 'http=%{http_code} bytes=%{size_download}\n'
echo "total_reported: $(grep -oE '"total": *[0-9]+' /tmp/s2375.json | head -1)"
echo "ip_str_found: $(grep -oE '"ip_str": *"[0-9.]+"' /tmp/s2375.json | wc -l)"
grep -oE '"ip_str": *"[0-9.]+"' /tmp/s2375.json | head -5
echo "== raw head =="
head -c 220 /tmp/s2375.json
echo
echo "== search: port:2375 country:DE (slice test) =="
curl -sS -m 25 "https://api.shodan.io/shodan/host/search?key=$K&query=port%3A2375%20country%3ADE" \
     -o /tmp/sde.json -w 'http=%{http_code} bytes=%{size_download}\n'
echo "total_reported: $(grep -oE '"total": *[0-9]+' /tmp/sde.json | head -1)"
echo "ip_str_found: $(grep -oE '"ip_str": *"[0-9.]+"' /tmp/sde.json | wc -l)"
