#!/bin/sh
# probe: on the "page not found" class, does the created container exist at all
# (a second create with the same name must 409 if it does), and does any spelling
# of start route (trailing slash / short id / detach)?
ip=$1
[ -n "$ip" ] || { echo usage: $0 ip; exit 2; }
api=$(curl -sS -m 5 "http://$ip:2375/version" | grep -o '"ApiVersion": *"[0-9.]*"' | head -1 | cut -d'"' -f4)
J='Content-Type: application/json'
B='{"Image":"alpine:3.19","Cmd":["sleep","600"]}'
echo "api=[$api]"
echo "create#1: [$(curl -sS -m 20 -X POST "http://$ip:2375/containers/create?name=zz$$" -H "$J" -d "$B" | head -c 70)]"
echo "create#2: [$(curl -sS -m 20 -X POST "http://$ip:2375/containers/create?name=zz$$" -H "$J" -d "$B" | head -c 130)]"
r=$(curl -sS -m 20 -X POST "http://$ip:2375/containers/create?name=yy$$" -H "$J" -d "$B")
id=$(printf '%s' "$r" | grep -oE '[0-9a-f]{64}' | head -1)
short=$(printf '%s' "$id" | cut -c1-12)
echo "id=[$short]"
for p in "/containers/$id/start/" "/containers/$short/start" "/containers/yy$$/start" "/v$api/containers/$id/start?detach=1"; do
    echo "start $p -> [$(curl -sS -m 15 -X POST "http://$ip:2375$p" | head -c 70)]"
done
echo "list all   : [$(curl -sS -m 10 "http://$ip:2375/containers/json?all=1" | head -c 170)]"
