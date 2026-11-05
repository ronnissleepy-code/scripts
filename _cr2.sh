#!/bin/sh
# pre-deploy sanity: no CRLF, new markers present, script still parses, unit test passes.
PATH="/usr/bin:$PATH"; export PATH
cd "$(dirname "$0" | tr -d '\r')" 2>/dev/null || cd .
exec > _all.out 2>&1
echo "== dock.sh preflight =="
echo "cr_lines=$(awk '/\r/{n++} END{print n+0}' dock.sh)"
echo "hint_flags=$(grep -c cpu-max-threads-hint dock.sh)"
echo "portmap_refs=$(grep -c PORTMAP dock.sh)"
echo "ram_refs=$(grep -c RAMFILE dock.sh)"
echo "ports_default=$(grep -c 'DOCK_PORTS:-2375' dock.sh)"
echo "cpu_shares_2048=$(grep -c 'CpuShares\\\":2048' dock.sh)"
if sh -n dock.sh; then echo "SYNTAX-OK"; else echo "SYNTAX-FAIL"; fi
echo "== unit test =="
sh _porttest2.sh
echo "rc=$?"
