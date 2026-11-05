#!/bin/sh
# throwaway: publish + record the resulting git state (so it survives a dead terminal)
PATH="/usr/bin:$PATH"; export PATH
cd "$(dirname "$0" | tr -d '\r')" 2>/dev/null || cd .
{
    sh publish.sh "perf: probe :2375 only for unverified candidates; RAM-ordered re-arm ledger; README"
    echo "publish_exit=$?"
    echo "HEAD=$(git rev-parse HEAD)"
    echo "ORIGIN=$(git rev-parse origin/main)"
    echo ---LOG:
    git log --oneline -2
    echo ---STATUS:
    git status --short | head -6
    echo "blob_portmap=$(git show HEAD:dock.sh | grep -c PORTMAP)"
    echo "blob_hint=$(git show HEAD:dock.sh | grep -c cpu-max-threads-hint)"
    echo "blob_readme=$(git show HEAD:README.md | grep -c big-host-first)"
} > _pub5.txt 2>&1
