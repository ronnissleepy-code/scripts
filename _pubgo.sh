#!/bin/sh
# throwaway: publish step-by-step, timestamped, no pager, no prompt - so a stall
# shows up as a missing step instead of silence.
cd "$(dirname "$0")" || exit 1
export GIT_TERMINAL_PROMPT=0
{
    date -u +%T
    echo "step: add"
    git --no-pager add -A
    echo "step: commit"
    if git diff --cached --quiet; then echo "(nothing to commit)"; else git -c user.name=k -c user.email=k@k commit -qm "readme: document the shodan DB filter + staleness caveat"; fi
    echo "step: push"
    git -c credential.helper=manager-core --no-pager push origin HEAD:main 2>&1 | tail -3
    echo "step: verify"
    git log --oneline -1
    git rev-parse --short origin/main
    echo "step: sha"
    sha256sum shodan.sh hunt.sh worker.env
    date -u +%T
} > _pub6.txt 2>&1
