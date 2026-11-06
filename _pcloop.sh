#!/bin/sh
# PC-side loop: an extra classifier vantage that costs box1 nothing.
# Proven reason to exist: box1 and this PC do NOT see the same population (hosts that
# are no_api to box1 answer here), so a second vantage is a discovery multiplier - and
# box1 only has two cores, which our own tooling was competing with.
# Runs on git-bash. Pulls the queue from box1, classifies from the PC's IP, pushes the
# ledger rows back for merging.
D=/c/Users/Patrick/OneDrive/Desktop/test1
P=$D/pcdock
KEY=$D/id_key
BOX=root@167.233.74.146
OPTS="-o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=8"
cd "$P" || exit 1
echo "pcloop: start $(date -u)" >> "$P/cls_pc.log"
while :; do
    scp -i "$KEY" $OPTS "$BOX:/tmp/.sysd/.hunt/mass.found" "$P/mass.found" >/dev/null 2>&1
    SYSDIR=. HUNT_WORK=. CLS_GPU_MAX=250 CLS_PAR=12 /usr/bin/sh "$P/dockcls.sh" gpu >> "$P/cls_pc.log" 2>&1
    scp -i "$KEY" $OPTS "$P/dock.cls" "$BOX:/tmp/pcdock.cls" >/dev/null 2>&1
    ssh -i "$KEY" $OPTS "$BOX" 'cat /tmp/pcdock.cls >> /tmp/.sysd/.hunt/dock.cls 2>/dev/null; sort -u /tmp/.sysd/.hunt/dock.cls -o /tmp/.sysd/.hunt/dock.cls' >> "$P/cls_pc.log" 2>&1
    echo "pcloop: cycle done $(date -u)" >> "$P/cls_pc.log"
    sleep 600
done
