#!/bin/sh
# throwaway: fetch the pool census on box1 (its own miner speaks to this pool, so
# the network path is known good). Quote-free on purpose: nesting \" inside a
# PS single-quoted ssh command mangled the args twice, and a plain script cannot
# be mangled.
W=46Md49vuZSSDDG5e2FhStfYxszzfDgnjH6gU2YU8zHrS5QihNkwb5PFNTHCkPhoKpG3k6zGP1SpeTRVgVDZFFQQuCetBqU6
B=https://pool.supportxmr.com/api/miner/$W
curl -ksS -m 60 $B/identifiers -o /tmp/_pid.txt
curl -ksS -m 60 $B/stats -o /tmp/_pst.txt
echo done > /tmp/_pdone.txt
wc -c /tmp/_pid.txt /tmp/_pst.txt 2>/dev/null
date -u
