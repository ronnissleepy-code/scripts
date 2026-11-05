#!/bin/sh
# throwaway: count CR per shipped file (0 = safe for dash)
cd "$(dirname "$0")" || exit 1
CR=$(printf '\r')
for f in *.sh worker.env *.service *.timer *.md; do
    [ -f "$f" ] || continue
    n=$(tr -cd "$CR" < "$f" | wc -c)
    printf '%3s  %s\n' "$n" "$f"
done
