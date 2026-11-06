#!/bin/sh
# throwaway: response headers + neighbouring ports.
# real dockerd sends "Server: Docker/<ver>" and "Api-Version" headers and only opens
# the daemon port; a fixture usually answers bare, on whatever port was invented.
for ip in "$@"; do
    echo "== $ip"
    echo "--- headers on /version (real dockerd: Server: Docker/x, Api-Version: 1.xx)"
    curl -sS -m 5 -D - -o /dev/null "http://$ip:2375/version" 2>/dev/null | tr -d '\r' | sed -n '1,12p'
    echo "--- root path body"
    curl -sS -m 5 "http://$ip:2375/" 2>/dev/null | head -c 120; echo
    echo "--- other daemon ports"
    for p in 2375 2376 4243 2377 8080 5000; do
        c=$(curl -sS -m 3 -o /dev/null -w '%{http_code}' "http://$ip:$p/version" 2>/dev/null) || c="x"
        printf '  :%s -> %s\n' "$p" "$c"
    done
done
