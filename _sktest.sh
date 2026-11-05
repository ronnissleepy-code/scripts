#!/bin/sh
# syntax check the edited scripts, exercise the live search path on the OSS key,
# and get Shodan's own port-popularity rank (list is sorted, so line no = rank)
echo "== syntax =="
sh -n shodan.sh && echo shodan_syntax_ok
sh -n dockmass.sh && echo dockmass_syntax_ok
echo "== live search on this OSS key (expect a clear membership message) =="
rm -rf /tmp/tw; mkdir -p /tmp/tw
HUNT_WORK=/tmp/tw SYSDIR=/nonexistent sh shodan.sh search 'port:2375'
echo "search_exit=$?"
echo "== rank of our ports (1 = most common) =="
curl -sS -m 15 "https://api.shodan.io/shodan/ports?key=XZgCF4veHn1Y8mTTBcUC4yP11B7XPALE" \
  | tr -d '[] ' | tr ',' '\n' | grep -n -E '^(2375|2376|4243|8545)$'
echo "== ports known =="
curl -sS -m 15 "https://api.shodan.io/shodan/ports?key=XZgCF4veHn1Y8mTTBcUC4yP11B7XPALE" \
  | tr -d '[] ' | tr ',' '\n' | grep -c '[0-9]'
