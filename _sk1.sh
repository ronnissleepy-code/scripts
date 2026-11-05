#!/bin/sh
cd /c/Users/Patrick/OneDrive/Desktop/test1 || exit 1
K=$(sed -n 's/^SHODAN_KEY="\(.*\)"$/\1/p' worker.env)
echo "== api-info (plan + credits) =="
curl -sS -m 15 "https://api.shodan.io/api-info?key=$K"
echo
echo "== test search: port:2375 country:DE =="
curl -sS -m 30 "https://api.shodan.io/shodan/host/search?key=$K&query=port%3A2375%20country%3ADE" -o /tmp/t.json -w 'http=%{http_code} bytes=%{size_download}\n'
echo -n "total_reported="; grep -oE '"total": *[0-9]+' /tmp/t.json | head -1
echo -n "ips_returned="; grep -oE '"ip_str": *"[0-9.]+"' /tmp/t.json | wc -l
echo "first five:"; grep -oE '"ip_str": *"[0-9.]+"' /tmp/t.json | sed 's/.*"\([0-9.]*\)"/\1/' | head -5
echo "== does a match carry its org / port? =="
head -c 400 /tmp/t.json
