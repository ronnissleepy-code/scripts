#!/bin/sh
# throwaway: box side of the CR/channel forensics (run via ssh, no quoting)
cd /tmp/.sysd || exit 1
echo BOX:
ls -l shodan.sh
wc -c shodan.sh
grep -c '"' shodan.sh
echo --- l30-33:
sed -n '30,33p' shodan.sh
echo --- syntax:
sh -n shodan.sh 2>&1 | head -3
echo --- rc:
sh -n shodan.sh >/dev/null 2>&1; echo "rc=$?"
echo --- md5:
md5sum shodan.sh
echo --- updater list:
grep -n 'for f in' updater.sh
