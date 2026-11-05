#!/bin/sh
# throwaway: publish + record the resulting git state (so it survives a dead terminal)
cd "$(dirname "$0")" || exit 1
{
    sh publish.sh "readme: document the shodan DB filter + its staleness caveat"
    echo ---HEAD:
    git log --oneline -2
    echo ---ORIGIN:
    git rev-parse --short origin/main
    echo ---STATUS:
    git status --short | head -5
    echo ---LOCAL_SHA:
    sha256sum shodan.sh hunt.sh worker.env
} > _pub5.txt 2>&1
