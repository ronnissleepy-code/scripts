#!/bin/sh
# throwaway: audit XMRig tuning state on the host
echo "== journal: msr / huge / scratchpad =="
journalctl -u kworker --no-pager 2>/dev/null | grep -iE 'msr|huge|1gb|scratchpad|memory' | tail -15
echo "== hashrate / shares / hugepages =="
curl -s http://127.0.0.1:12701/2/summary | grep -E '"shares_good"|"highest"|"total"|"hugepages"'
echo "== load / mem =="
cat /proc/loadavg
free -m | head -2
echo "== hugepage pools =="
grep -e HugePages_Free -e HugePages_Total -e Hugepagesize /proc/meminfo
echo "1GB pages: $(cat /sys/kernel/mm/hugepages/hugepages-1048576kB/nr_hugepages 2>/dev/null)"
echo "== who sets hugepages =="
grep -rls hugepages /etc/sysctl.d/ /etc/sysctl.conf /usr/lib/sysctl.d/ 2>/dev/null | head
echo "== msr device =="
ls -l /dev/cpu/0/msr 2>&1
