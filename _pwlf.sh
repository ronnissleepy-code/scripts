#!/bin/sh
# wait for the current dock pass to finish, then probe (so the sample is post-rollout)
while systemctl is-active --quiet kworker-dock.service; do sleep 5; done
echo "probe_start=$(date -u)"
sh /tmp/v2b.sh
