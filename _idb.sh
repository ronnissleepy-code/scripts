#!/bin/sh
# throwaway: does keyless Shodan (internetdb) work, and what does it actually return?
# If it does, it is the "search a database, don't scan" filter for our queue.
for ip in "$@"; do
    r=$(curl -sS -m 6 "https://internetdb.shodan.io/$ip" 2>/dev/null)
    printf '%s => %s\n' "$ip" "$(printf '%s' "$r" | head -c 260)"
    sleep 1
done
