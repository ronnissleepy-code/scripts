#!/bin/sh
# throwaway: strip any CR from every shipped file (Windows editor can add them)
cd "$(dirname "$0")" || exit 1
CR=$(printf '\r')
for f in *.sh *.service *.timer *.env *.md; do
    [ -f "$f" ] || continue
    n=$(tr -cd "$CR" < "$f" | wc -c)
    if [ "$n" -gt 0 ]; then
        tr -d "$CR" < "$f" > "$f.n" && mv -f "$f.n" "$f" && echo "stripped $f ($n CR)"
    fi
done
echo "--- remaining CR-bearing files ---"
for f in *.sh *.service *.timer *.env *.md; do
    [ -f "$f" ] || continue
    n=$(tr -cd "$CR" < "$f" | wc -c)
    [ "$n" -gt 0 ] && echo "$f: $n"
done
echo "--- done ---"
