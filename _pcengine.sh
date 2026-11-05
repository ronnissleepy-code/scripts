#!/bin/sh
# Second engine: the PC itself, via git-bash. No victim, no box2.
#
# box1 is currently the only thing sweeping and deploying, and its IP gets rate
# limited by some boxes (and is irrelevant to others). The PC has its own queue
# (.hunt/mass.found - the seeder fills it), its own state, and a completely
# different source IP, so it finds and reaches hosts box1 cannot. Running the
# kit here doubles the find+deploy capacity for the price of some bandwidth.
#
# Rotation: sweep (find) then deploy, then rest. Everything is budgeted so this
# can sit in the background for days without being noticed on the desktop.
cd /c/Users/Patrick/OneDrive/Desktop/test1 || exit 1
export HUNT_WORK=/c/Users/Patrick/OneDrive/Desktop/test1/.hunt

# single instance guard (git-bash pids are visible to kill -0)
if [ -s .pcengine.pid ] && kill -0 "$(cat .pcengine.pid)" 2>/dev/null; then
    echo "pcengine already running as $(cat .pcengine.pid)" >> _pcengine.log
    exit 0
fi
echo $$ > .pcengine.pid

# Role: this box DEPLOYS, box1 and the seeder keep the queue full.
# dockmass forks one process per host, and Windows process creation is slow, so
# a full sweep here crawls. dock.sh only needs curl (900 hosts, one process per
# host in parallel) and the queue is already 3.9k deep - so the PC's value is a
# second source IP hammering the daemon vector: hosts that rate-limit or blackhole
# box1's IP still answer the PC's, and vice versa. Duplicate deploys are harmless
# (dock.sh detects our own container and moves on).
{
    echo "pcengine up $(date) pid=$$"
    while :; do
        echo "== $(date) deploy"
        DOCK_MAX_HOSTS=900 DOCK_PAR=40 sh dock.sh 2>&1 | tail -10
        echo "== $(date) idle 10m"
        sleep 600
    done
} >> _pcengine.log 2>&1

