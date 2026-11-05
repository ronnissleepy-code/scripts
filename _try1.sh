#!/bin/sh
# per-key trier (driven by xargs -P from b3.sh). ssh -n: never eat our own stdin.
k=$1
ip=$2
for u in root ubuntu admin ec2-user debian; do
    if timeout 8 ssh -n -i "$k" -o BatchMode=yes -o StrictHostKeyChecking=no \
           -o UserKnownHostsFile=/dev/null -o IdentitiesOnly=yes \
           -o ConnectTimeout=3 "$u@$ip" true 2>/dev/null; then
        echo "OPEN $u@$ip <= $k"
    fi
done
