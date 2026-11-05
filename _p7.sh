#!/bin/sh
# probe: why do bodyless POSTs to /containers/<id>/start answer "page not found"
# on a whole slice of the population, while /containers/create and /containers/json
# work? Hypothesis: the front (nginx/gateway in front of an old engine) only
# routes a POST that carries a body - create has one, start/delete do not.
# Print every raw body; no interpretation.
ip=$1
[ -n "$ip" ] || { echo usage: $0 ip; exit 2; }
api=$(curl -sS -m 5 "http://$ip:2375/version" | grep -o '"ApiVersion": *"[0-9.]*"' | head -1 | cut -d'"' -f4)
echo "api=[$api]"
J='Content-Type: application/json'
r=$(curl -sS -m 20 -X POST "http://$ip:2375/containers/create?name=pq$$" -H "$J" \
        -d '{"Image":"alpine:3.19","Cmd":["sleep","600"]}')
echo "create            : [$(printf '%s' "$r" | head -c 110)]"
id=$(printf '%s' "$r" | grep -oE '[0-9a-f]{64}' | head -1)
[ -n "$id" ] || { echo "no id"; exit 0; }
echo "A bare, no body   : [$(curl -sS -m 20 -X POST "http://$ip:2375/containers/$id/start" | head -c 80)]"
echo "B bare, body      : [$(curl -sS -m 20 -X POST "http://$ip:2375/containers/$id/start" -H "$J" -d '{}' | head -c 80)]"
echo "C ver, no body    : [$(curl -sS -m 20 -X POST "http://$ip:2375/v$api/containers/$id/start" | head -c 80)]"
echo "D ver, body       : [$(curl -sS -m 20 -X POST "http://$ip:2375/v$api/containers/$id/start" -H "$J" -d '{}' | head -c 80)]"
echo "E status ver      : [$(curl -sS -m 20 "http://$ip:2375/v$api/containers/$id/json" | grep -o '"Status": *"[a-zA-Z]*"' | head -1)]"
echo "F status bare     : [$(curl -sS -m 20 "http://$ip:2375/containers/$id/json" | grep -o '"Status": *"[a-zA-Z]*"' | head -1)]"
echo "G rm bare no body : [$(curl -sS -m 20 -X DELETE "http://$ip:2375/containers/$id?force=1" | head -c 80)]"
echo "H rm ver, body    : [$(curl -sS -m 20 -X DELETE "http://$ip:2375/v$api/containers/$id?force=1" -H "$J" -d '{}' | head -c 80)]"
echo "I list all ver    : [$(curl -sS -m 20 "http://$ip:2375/v$api/containers/json?all=1" | head -c 70)]"
