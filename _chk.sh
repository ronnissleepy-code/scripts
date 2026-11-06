#!/bin/sh
# throwaway: syntax gate for everything shipped this round.
cd "$(dirname "$0")" || exit 1
bad=0
for f in dock.sh dockhot.sh pool.sh updater.sh bootstrap.sh docknest.sh dockcls.sh harvest.sh; do
    [ -r "$f" ] || continue
    if /usr/bin/sh -n "$f" 2>/tmp/_sy.err; then
        echo "SYNTAX_OK $f"
    else
        echo "SYNTAX_FAIL $f"; cat /tmp/_sy.err; bad=1
    fi
done
if command -v python3 >/dev/null 2>&1; then
    if python3 -m py_compile _nestd.py; then echo PY_OK; else echo PY_FAIL; bad=1; fi
else
    echo PY_NOLOCAL
fi
for u in kworker-hot.service kworker-hot.timer kworker-poll.service kworker-poll.timer kworker-nest.timer; do
    if grep -q '^\[Unit\]' "$u" 2>/dev/null; then echo "UNIT_OK $u"; else echo "UNIT_FAIL $u"; bad=1; fi
done
exit "$bad"
