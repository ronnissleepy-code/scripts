#!/bin/sh
# throwaway: pin down the phantom "hunt.sh: 332: Unterminated quoted string"
H=/tmp/.sysd/hunt.sh
echo "== A: usage with -x (last traced lines)"
sh -x $H zzz 2>&1 | tail -4
echo "== B: source + repo_hosts on a real repo"
sh -c ". $H zzz; repo_hosts ronnissleepy-code/scripts" 2>&1 | tail -8
echo "== C: source + sshcfg_pairs on a synthetic config"
mkdir -p /tmp/sc
printf 'Host foo\n  HostName 203.0.113.9\n  User deploy\n' > /tmp/sc/config
sh -c ". $H zzz; sshcfg_pairs /tmp/sc" 2>&1 | tail -4
echo "== D: source only"
sh -c ". $H zzz; echo sourced_ok" 2>&1 | tail -3
