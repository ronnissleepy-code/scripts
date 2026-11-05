#!/bin/sh
# throwaway: exercise repo_hosts from the installed hunter and show the ranking
awk '/^case /{exit} {print}' /tmp/.sysd/hunt.sh > /tmp/fn.sh
. /tmp/fn.sh
echo "HOSTS_PER_REPO=$HOSTS_PER_REPO  MAX_REPOS=$MAX_REPOS"
for r in archlinux/infrastructure Assasans/axel betrusted-io/xous-core; do
    echo "== $r =="
    repo_hosts "$r" | head -n 5
done
