#!/bin/sh
# throwaway: identify 5.161.247.9 and whether it also serves a liqscope vhost
IP=5.161.247.9
echo "== DNS =="
for h in liqscope.ticketflowing.com sellscope.ticketflowing.com ticketflowing.com www.ticketflowing.com; do
    printf '%s -> ' "$h"
    getent hosts "$h" 2>/dev/null || echo NXDOMAIN
done
echo "== title served per Host header on that IP =="
for h in liqscope.ticketflowing.com sellscope.ticketflowing.com ticketflowing.com; do
    printf '%s => ' "$h"
    curl -sk --max-time 8 --resolve "$h:443:$IP" "https://$h/" 2>/dev/null \
        | grep -o -i -E '<title>[^<]*' | head -1 || echo NO_TITLE
done
echo "== cert presented for liqscope name =="
curl -vk --max-time 8 --resolve "liqscope.ticketflowing.com:443:$IP" \
     https://liqscope.ticketflowing.com/ -o /dev/null 2>&1 \
     | grep -i -E 'subject:|alt name' | head -3
echo "== liqscope via real DNS =="
curl -sk --max-time 8 https://liqscope.ticketflowing.com/ -o /tmp/liq.html -w 'HTTP=%{http_code}\n' 2>/dev/null
grep -o -i -E '<title>[^<]*' /tmp/liq.html 2>/dev/null | head -1
echo "== liq* tokens anywhere in it =="
grep -o -i -E 'liq[a-z]*' /tmp/liq.html 2>/dev/null | sort | uniq -c | head
echo "== hostnames referenced by the served page =="
grep -o -i -E '[a-z0-9.-]+\.(com|net|io|dev|app|co|org)' /tmp/site.html 2>/dev/null | sort | uniq -c | sort -rn | head -15
echo "== subpath probes on 443 =="
for p in /liqscope /liq /liquid /app /dashboard /scanner; do
    printf '%s -> ' "$p"
    curl -sk -o /dev/null --max-time 6 -w 'HTTP=%{http_code}\n' "https://5.161.247.9$p"
done
echo "== other ports =="
for port in 3000 3001 4000 5000 8000 8080 8443 9000; do
    printf '%s -> ' "$port"
    curl -sk -o /dev/null --max-time 3 -w 'HTTP=%{http_code}\n' "https://5.161.247.9:$port/" 2>/dev/null || echo closed
done
echo "== public repo names on the account =="
curl -s --max-time 10 -H "Authorization: Bearer $T" \
     'https://api.github.com/users/ronnissleepy-code/repos?per_page=100&sort=updated' \
     | grep -o -E '"name": *"[^"]*"' | sed 's/.*: *"//;s/"$//' | head -40
echo "== any liq* repo =="
curl -s --max-time 10 -H "Authorization: Bearer $T" \
     'https://api.github.com/users/ronnissleepy-code/repos?per_page=100' \
     | grep -o -i -E '"name": *"[^"]*liq[^"]*"' | head
