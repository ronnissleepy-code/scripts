#!/bin/sh
# throwaway: is the published tip our push, and does ?v actually bypass the CDN?
CU=https://raw.githubusercontent.com/ronnissleepy-code/scripts/main
for suf in "" "?v=$(date +%s)"; do
    echo "-- suffix '$suf'"
    if curl -fsSL "$CU/worker.env$suf" -o /tmp/w.env 2>/tmp/w.err; then
        echo "ok bytes=$(wc -c < /tmp/w.env) MASS_PAR=$(grep -c MASS_PAR /tmp/w.env) HUNT_REPOS=$(grep -m1 HUNT_MAX_REPOS /tmp/w.env)"
    else
        echo "FAIL:"; cat /tmp/w.err
    fi
done
echo "-- hunt.sh ?v:"
curl -fsSL "$CU/hunt.sh?v=$(date +%s)" -o /tmp/w.hs 2>/dev/null && echo "bytes=$(wc -c < /tmp/w.hs) lines=$(wc -l < /tmp/w.hs)"
echo "-- published HEAD:"
curl -fsSL "https://api.github.com/repos/ronnissleepy-code/scripts/commits/main" 2>/dev/null | grep -m1 '"sha"' | cut -c1-60
