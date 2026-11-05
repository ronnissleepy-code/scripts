#!/bin/sh
# throwaway: syntax-check every shipped script (git-bash sh is bash; box has dash)
cd "$(dirname "$0")" || exit 1
for f in shodan.sh hunt.sh loot.sh dock.sh dockmass.sh spread.sh bootstrap.sh updater.sh run.sh tune.sh publish.sh; do
    printf '%s: ' "$f"
    if sh -n "$f" 2>/tmp/syn.e; then echo OK; else echo FAIL; cat /tmp/syn.e; fi
done
