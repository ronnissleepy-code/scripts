#!/bin/sh
# throwaway: fast final verification on the box (no long runs, so ssh returns)
cd /tmp/.sysd || exit 1
echo ---sha256:
sha256sum shodan.sh hunt.sh worker.env
echo ---hunt wiring:
grep -c shodan_now hunt.sh
grep -n 'shodan)' hunt.sh
echo ---hunt all line:
grep -n 'all)' hunt.sh
echo ---idb:
wc -l .hunt/idb.txt .hunt/idb.dead .hunt/crypto.txt
echo ---scout:
cat /tmp/scout.out
echo ---dock state:
cat .hunt/mass.found
