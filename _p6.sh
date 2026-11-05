#!/bin/sh
# probe: is the unversioned-vs-versioned routing the whole story, or is start
# refused for a different reason entirely? Print every raw body, no guessing.
ip=$1
[ -n "$ip" ] || { echo usage: $0 ip; exit 2; }
echo "-- version: $(curl -sS -m 5 "http://$ip:2375/version" | head -c 200)"
api=$(curl -sS -m 5 "http://$ip:2375/version" | grep -o '"ApiVersion": *"[0-9.]*"' | head -1 | cut -d'"' -f4)
echo "api=[$api]"
nm=pb$$
body="{\"Image\":\"alpine:3.19\",\"Cmd\":[\"sleep\",\"600\"]}"
if ! curl -fsS -m 6 "http://$ip:2375/images/alpine:3.19/json" >/dev/null 2>&1; then
    echo "-- pulling"; curl -sS -m 120 -X POST "http://$ip:2375/images/create?fromImage=alpine:3.19" >/dev/null 2>&1
fi
r=$(curl -sS -m 20 -X POST "http://$ip:2375/containers/create?name=$nm" -H Content-Type:application/json -d "$body")
echo "-- create: $(printf '%s' "$r" | head -c 200)"
id=$(printf '%s' "$r" | grep -oE '[0-9a-f]{64}' | head -1)
echo "id=${id%??????????????????????????????????????????????????????}"
echo "-- start bare: [$(curl -sS -m 20 -X POST "http://$ip:2375/containers/$id/start" | head -c 200)]"
echo "-- start v$api: [$(curl -sS -m 20 -X POST "http://$ip:2375/v$api/containers/$id/start" | head -c 200)]"
echo "-- inspect v: [$(curl -sS -m 8 "http://$ip:2375/v$api/containers/$id/json" | head -c 240)]"
echo "-- state: [$(curl -sS -m 8 "http://$ip:2375/v$api/containers/$id/json" | grep -o '"Status": *"[a-z]*"')]"
echo "-- rm: [$(curl -sS -m 15 -X DELETE "http://$ip:2375/v$api/containers/$id?force=1" | head -c 120)]"
