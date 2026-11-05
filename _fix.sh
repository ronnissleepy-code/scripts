#!/bin/sh
# throwaway: recover miner after the 1GB page experiment + persist the 2M pool
if [ ! -f /etc/sysctl.d/99-kworker-hugepages.conf ]; then
    echo "vm.nr_hugepages=1340" > /etc/sysctl.d/99-kworker-hugepages.conf
    echo "wrote /etc/sysctl.d/99-kworker-hugepages.conf"
fi
sysctl -w vm.nr_hugepages=1340 >/dev/null
echo "2M pool now: $(cat /proc/sys/vm/nr_hugepages)  1G pool: $(cat /sys/kernel/mm/hugepages/hugepages-1048576kB/nr_hugepages)"
systemctl start kworker
sleep 18
echo "service: $(systemctl is-active kworker)"
journalctl -u kworker --no-pager | grep -iE 'huge pages|threads|READY' | tail -4
