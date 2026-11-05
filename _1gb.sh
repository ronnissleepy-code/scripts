#!/bin/sh
# throwaway: try to reserve 1GB hugepages for the RandomX dataset
echo "before: $(grep -e MemFree /proc/meminfo)"
systemctl stop kworker
sleep 2
sysctl -w vm.nr_hugepages=64 >/dev/null
sleep 3
echo "released 2M pool: $(grep -e HugePages_Free -e MemFree /proc/meminfo | tr '\n' ' ')"
for n in 3 2 1; do
    if echo "$n" > /sys/kernel/mm/hugepages/hugepages-1048576kB/nr_hugepages 2>/dev/null; then
        got=$(cat /sys/kernel/mm/hugepages/hugepages-1048576kB/nr_hugepages)
        echo "requested ${n}G -> got ${got}"
        [ "$got" = "$n" ] && break
    else
        echo "requested ${n}G -> write failed"
    fi
done
echo "final pools: $(cat /sys/kernel/mm/hugepages/hugepages-1048576kB/nr_hugepages) x 1G / $(cat /proc/sys/vm/nr_hugepages) x 2M"
grep -e MemFree -e MemAvailable /proc/meminfo
systemctl start kworker
echo started
