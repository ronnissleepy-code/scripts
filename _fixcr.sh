#!/bin/sh
# throwaway: strip any CR from every shipped file (Windows editor can add them)
cd "$(dirname "$0")" || exit 1
CR=$(printf '\r')
for f in *.sh *.service *.timer; do
    [ -f "$f" ] || continue
    if grep -q "$CR" "$f" 2>/dev/null; then
        tr -d "$CR" < "$f" > "$f.n" && mv -f "$f.n" "$f" && echo "stripped $f"
    fi
done
echo "--- done ---"
