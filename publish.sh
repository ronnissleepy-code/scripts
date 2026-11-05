#!/bin/sh
# ============================================================================
# Publish: push this kit to the URL the fleet fetches from (CONFIG_URL).
#
# The vector is git, not files. bootstrap.sh and updater.sh pull from
# CONFIG_URL, so an edit that is only committed - or only scp'd onto one box -
# is invisible to the fleet. Worse, the updater on every host will quietly
# revert that host to the published copy at its next tick, so "it worked when I
# tested it" decays within 15 minutes. Publish, or it did not happen.
#
# The GITHUB_TOKEN in worker.env is enough for the harvester, but it is usually
# read-only (an empty X-OAuth-Scopes header), so the push falls back to your OS
# git credential - which is why this only needs a working `git push` setup.
#
# usage: publish.sh ["commit message"]
# ============================================================================
set -eu
SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$SELF_DIR" || exit 1
[ -r worker.env ] || { echo "publish: no worker.env here"; exit 1; }
. ./worker.env

: "${CONFIG_URL:?set CONFIG_URL in worker.env}"
REPO=$(printf '%s' "$CONFIG_URL" | sed -e 's|https://raw.githubusercontent.com/||' -e 's|/[^/]*$||')
BRANCH=$(printf '%s' "$CONFIG_URL" | sed -e 's|.*/||')
echo "publish: $REPO (branch $BRANCH)"

CR=$(printf '\r')
# Windows editors write CRLF. dash treats the stray CR as part of the last word on
# the line, so a script delivered by scp (rather than fetched via git/raw, which
# normalises) fails with "Syntax error: 'done' unexpected". Normalise first: the
# working tree, the commit and anything scp'd from here are then LF.
for f in *.sh *.service *.timer *.env *.txt; do
    [ -f "$f" ] || continue
    if [ "$(tr -cd "$CR" < "$f" | wc -c)" -gt 0 ]; then
        tr -d "$CR" < "$f" > "$f.n" && mv -f "$f.n" "$f" && echo "publish: stripped CR from $f"
    fi
done

git add -A
if git diff --cached --quiet; then
    echo "publish: nothing to commit"
else
    git commit -qm "${1:-publish: sync kit}"
fi
git push origin "HEAD:$BRANCH"
git log --oneline -1
