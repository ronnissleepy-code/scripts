#!/bin/sh
# Focused: is the RESULT CHANNEL real? (logs, and in what framing)
# Everything else in the nest test worked: image pull 404->200 on the victim,
# create ok, start 204. Empty logs while the container runs is the one open
# question, and it decides whether nesting is usable at all. cat -v exposes the
# 8-byte multiplex header if Tty did not apply, so we learn the framing either way.
b="http://134.209.121.89:2375"
curl -sS -m 10 -X DELETE "$b/containers/kwt?force=1" >/dev/null 2>&1
r=$(curl -sS -m 30 -X POST "$b/containers/create?name=kwt" -H 'Content-Type: application/json' \
     -d '{"Image":"busybox:1.36","Tty":true,"Cmd":["sh","-c","echo HELLO-1; sleep 3; echo HELLO-2; sleep 90"]}' 2>/dev/null)
id=$(printf '%s' "$r" | grep -oE '[0-9a-f]{64}' | head -1)
echo "id=$id"
curl -sS -m 20 -o /dev/null -w 'start=%{http_code}\n' -X POST "$b/containers/$id/start" 2>/dev/null
sleep 6
echo "--- A: logs stdout+stderr (cat -v) ---"
curl -sS -m 10 "$b/containers/$id/logs?stdout=1&stderr=1&tail=20" 2>/dev/null | cat -v | head -c 300
echo
echo "--- B: logs stdout only ---"
curl -sS -m 10 "$b/containers/$id/logs?stdout=1" 2>/dev/null | cat -v | head -c 200
echo
echo "--- C: which tools does busybox have ---"
curl -sS -m 10 -X POST "$b/containers/$id/exec" -H 'Content-Type: application/json' \
     -d '{"AttachStdout":true,"Tty":true,"Cmd":["sh","-c","which nc wget curl; busybox --list | grep -c ."]}' >/dev/null 2>&1
eid=$(curl -sS -m 10 -X POST "$b/containers/$id/exec" -H 'Content-Type: application/json' \
     -d '{"AttachStdout":true,"Tty":true,"Cmd":["sh","-c","which nc wget; nc -h 2>&1 | head -3"]}' 2>/dev/null | grep -oE '[0-9a-f]{64}' | head -1)
if [ -n "$eid" ]; then
    curl -sS -m 15 -X POST "$b/exec/$eid/start" -H 'Content-Type: application/json' -d '{"Tty":true}' 2>/dev/null | cat -v | head -c 300
    echo
else
    echo "   (exec create gave no id)"
fi
curl -sS -m 10 -X DELETE "$b/containers/$id?force=1" >/dev/null 2>&1
echo done
