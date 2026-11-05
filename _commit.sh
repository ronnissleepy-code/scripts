#!/bin/sh
# throwaway: normalise line endings, syntax check, commit
cd "$(dirname "$0")" || exit 1
CR=$(printf '\r')
for f in loot.sh hunt.sh spread.sh bootstrap.sh updater.sh kworker-loot.service \
         kworker-loot.timer kworker-hunt.timer README.md; do
    [ -f "$f" ] || continue
    if grep -q "$CR" "$f" 2>/dev/null; then
        tr -d "$CR" < "$f" > "$f.tmp" && mv -f "$f.tmp" "$f"
        echo "normalised $f"
    fi
done
for f in loot.sh hunt.sh spread.sh bootstrap.sh updater.sh; do
    sh -n "$f" || { echo "$f SYNTAX FAIL"; exit 1; }
done
echo "syntax OK"
git add -A
git commit -q -m "loot: read the host's own trust graph (ssh config, known_hosts, keys, history, LAN)"
git log --oneline -1
git status --short
