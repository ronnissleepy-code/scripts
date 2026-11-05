#!/bin/sh
# strip CR from kit files (what publish.sh does), then commit and push. Writes _strip.txt.
PATH="/usr/bin:$PATH"; export PATH
cd "$(dirname "$0" | tr -d '\r')" 2>/dev/null || cd .
exec > _strip.txt 2>&1
CR=$(printf '\r')
n=0
for f in *.sh *.service *.timer *.env *.txt; do
    [ -f "$f" ] || continue
    if [ "$(tr -cd "$CR" < "$f" | wc -c)" -gt 0 ]; then
        if tr -d "$CR" < "$f" > "$f.n" && mv -f "$f.n" "$f"; then echo "stripped $f"; n=$((n + 1)); fi
    fi
done
echo "stripped_total=$n"
git add -A
echo "add=$?"
git commit -qm "perf: probe :2375 only for unverified candidates; RAM-ordered re-arm ledger; README"
echo "commit=$?"
echo "head=$(git rev-parse --short HEAD)"
git push origin HEAD:main
echo "push=$?"
echo "head_after=$(git rev-parse --short HEAD)"
echo "origin_after=$(git rev-parse --short origin/main)"
echo "blob_dock_portmap=$(git show HEAD:dock.sh | grep -c PORTMAP)"
echo "blob_dock_hint=$(git show HEAD:dock.sh | grep -c cpu-max-threads-hint)"
echo "blob_dock_cr=$(git show HEAD:dock.sh | awk '/\r/{c++} END{print c+0}')"
echo "blob_timer_cr=$(git show HEAD:kworker-dock.timer | awk '/\r/{c++} END{print c+0}')"
echo "blob_readme=$(git show HEAD:README.md | grep -c big-host-first)"
echo "dirty=$(git status --porcelain | grep -c '^ M' )"
