#!/bin/sh
# throwaway: where does "hunt.sh: 332: Unterminated quoted string" come from?
H=/tmp/.sysd/hunt.sh
echo "wc -l: $(wc -l < $H)"
echo "awk NR: $(awk 'END { print NR }' $H)"
echo "last 3 lines:"; tail -3 $H | cat -A | tail -3
echo "sh -n:"; sh -n $H 2>&1; echo "rc=$?"
echo "usage mode (no work):"; sh $H zzz 2>&1; echo "rc=$?"
echo "source worker.env:"; ( . /tmp/.sysd/worker.env; echo "sourced ok" ) 2>&1; echo "rc=$?"
echo "worker.env last line:"; tail -1 /tmp/.sysd/worker.env | cat -A
echo "updater mid-swap check: ls -l $H"
ls -l $H
