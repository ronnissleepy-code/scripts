#!/bin/sh
# wait for any dock pass to finish, then take a clean rollout sample
while pgrep -f '/tmp/.sysd/dock.sh' >/dev/null; do sleep 5; done
sleep 5
rm -f /tmp/_ver2b.out
sh /tmp/v2b.sh
