#!/bin/sh
# throwaway: run the hunter harvest from a clean slate, with a trace
rm -rf /tmp/.sysd/.hunt
echo "START $(date -u +%T)"
sh -x /tmp/.sysd/hunt.sh harvest 2>&1 | tail -60
echo "END $(date -u +%T)"
echo "== urls.txt lines =="; wc -l < /tmp/.sysd/.hunt/urls.txt 2>/dev/null
echo "== repos processed =="; cat /tmp/.sysd/.hunt/repos.txt 2>/dev/null
echo "== keys kept =="; ls -la /tmp/.sysd/.hunt/keys/ 2>/dev/null
echo "== TARGETS =="; cat /tmp/.sysd/.hunt/targets.txt 2>/dev/null
