#!/bin/sh
# throwaway: does the endpoint REMEMBER a create?
# real dockerd: create=201 and the new container is in the list from then on.
# fixture:      create=200 (an ack) and it never appears anywhere.
ip="$1"
b="http://$ip:2375"
echo "== create/forget probe $ip"
before=$(curl -sS -m 6 "$b/containers/json?all=1" 2>/dev/null | tr -d '\r\n' | grep -o '"Id"' | wc -l | tr -d ' ')
echo "before_ids=$before"
c=$(curl -sS -m 8 -X POST -H 'Content-Type: application/json' \
     -d '{"Image":"alpine","Cmd":["sleep","3600"]}' "$b/containers/create?name=kwrealprobe" \
     -w 'CODE=%{http_code}' 2>/dev/null)
printf 'create: %s   (real dockerd: 201)\n' "$(printf '%s' "$c" | head -c 200)"
printf 'create-id: %s\n' "$(printf '%s' "$c" | grep -o '"Id":"[^"]*"' | head -1 | cut -d'"' -f4)"
after=$(curl -sS -m 6 "$b/containers/json?all=1" 2>/dev/null | tr -d '\r\n' | grep -o '"Id"' | wc -l | tr -d ' ')
echo "after_ids=$after"
echo "names-in-list: $(curl -sS -m 6 "$b/containers/json?all=1" 2>/dev/null | tr -d '\r' | grep -o -e kwrealprobe -e kworker -e web-app | sort | uniq -c | tr '\n' ' ')"
byid=$(curl -sS -m 6 -o /dev/null -w '%{http_code}' "$b/containers/kwrealprobe/json" 2>/dev/null)
echo "GET-by-created-name=$byid"
