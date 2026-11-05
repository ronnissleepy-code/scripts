#!/bin/sh
# throwaway: install docker on the host and expose a :2375 listener so dock.sh
# has a real daemon to attack. Logs everything to /tmp/apt.log.
export DEBIAN_FRONTEND=noninteractive
{
    echo "== start $(date -u +%T) =="
    apt-get update -qq
    apt-get install -y -qq docker.io
    DK=$(command -v dockerd || echo /usr/sbin/dockerd)
    echo "dockerd=$DK"
    mkdir -p /etc/systemd/system/docker.service.d
    printf '[Service]\nExecStart=\nExecStart=%s -H fd:// -H tcp://0.0.0.0:2375\n' \
        "$DK" > /etc/systemd/system/docker.service.d/tcp.conf
    systemctl daemon-reload
    systemctl enable --now docker
    systemctl restart docker
    sleep 4
    echo "docker=$(systemctl is-active docker)"
    ss -tln | grep 2375
    curl -s --max-time 4 http://127.0.0.1:2375/version | head -c 200
    echo
    echo "== done $(date -u +%T) =="
} > /tmp/apt.log 2>&1
echo DONE >> /tmp/apt.log
