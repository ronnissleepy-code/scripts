#!/bin/sh
# throwaway: syntax check every shipped script
cd "$(dirname "$0")" || exit 1
for f in loot.sh dock.sh hunt.sh spread.sh bootstrap.sh updater.sh run.sh tune.sh; do
    if sh -n "$f" 2>/tmp/synerr; then
        echo "$f OK"
    else
        echo "$f FAIL:"
        cat /tmp/synerr
    fi
done
