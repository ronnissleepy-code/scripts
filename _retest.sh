#!/bin/sh
# throwaway: does the strict ipv4 pattern accept addresses and reject versions?
RE='\b(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])(\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])){3}\b'
for s in 00.00.01.01 1.0.0.0 192.168.1.5 46.182.19.48 101.3.4.2 256.1.1.1 1.32.6.25 11.2.9.1 999.1.1.1; do
    m=$(printf '%s\n' "$s" | grep -oE "$RE")
    printf '%-16s -> [%s]\n' "$s" "${m:-REJECTED}"
done
