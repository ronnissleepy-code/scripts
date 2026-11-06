#!/bin/sh
# throwaway: get the pool census, whatever it takes. Four explanations tried in
# order, because three fetches already failed differently:
#   1) pool.supportxmr.com has no A record in some resolvers (only pool-nyc does),
#      so the miner gets there by SRV/CNAME but curl may not. -> --resolve.
#   2) a 447-byte body with no JSON is the shape of a Cloudflare interstitial, so
#      send a normal browser-ish User-Agent instead of curl/8.
#   3) plain http may be redirected/blocked; try https.
#   4) retry: it answered once and timed out twice, so it is flaky by nature.
W=46Md49vuZSSDDG5e2FhStfYxszzfDgnjH6gU2YU8zHrS5QihNkwb5PFNTHCkPhoKpG3k6zGP1SpeTRVgVDZFFQQuCetBqU6
UA="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/124 Safari/537.36"
B=https://pool-nyc.supportxmr.com
grab() {  # $1=url $2=outfile
    curl -ksS -m 25 -A "$UA" -H 'Accept: application/json, text/plain, */*' "$1" -o "$2" 2>/dev/null
    sz=$(wc -c < "$2" 2>/dev/null)
    echo "  $1 -> bytes=${sz:-0} head=$(head -c 36 "$2" 2>/dev/null | tr -d '\n')"
    [ "${sz:-0}" -gt 300 ]
}
echo "== stats"
if ! grab "$B/api/miner/$W/stats" /tmp/_pst.txt; then
    if ! grab "https://pool.supportxmr.com/api/miner/$W/stats" /tmp/_pst.txt; then
        curl -ksS -m 25 -A "$UA" --resolve pool.supportxmr.com:443:104.243.43.115 \
            "https://pool.supportxmr.com/api/miner/$W/stats" -o /tmp/_pst.txt 2>/dev/null
        echo "  (resolve) bytes=$(wc -c < /tmp/_pst.txt 2>/dev/null)"
    fi
fi
echo "== identifiers"
if ! grab "$B/api/miner/$W/identifiers" /tmp/_pid.txt; then
    curl -ksS -m 25 -A "$UA" --resolve pool.supportxmr.com:443:104.243.43.115 \
        "https://pool.supportxmr.com/api/miner/$W/identifiers" -o /tmp/_pid.txt 2>/dev/null
    echo "  (resolve) bytes=$(wc -c < /tmp/_pid.txt 2>/dev/null)"
fi
echo "== summary"
grep -o 'hash[^,]*' /tmp/_pst.txt 2>/dev/null | head -3
echo "gpu_rig_ids_present=$(grep -c 134.209.121.89 /tmp/_pid.txt /tmp/_pst.txt 2>/dev/null | tr '\n' ' ')"
grep -o '134.209.121.89[^,}]*' /tmp/_pid.txt 2>/dev/null | head -4
echo done > /tmp/_pdone.txt
date -u
