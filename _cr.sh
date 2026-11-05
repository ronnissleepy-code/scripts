#!/bin/sh
# throwaway: count CRs per file, then strip them with sed -i
cd "$(dirname "$0")" || exit 1
echo "--- before ---"
for f in *.sh *.service *.timer *.md bootstrap.sh; do
    [ -f "$f" ] || continue
    n=$(tr -cd '\r' < "$f" | wc -c)
    [ "$n" -gt 0 ] && echo "$f: $n CR"
done
echo "--- stripping ---"
for f in *.sh *.service *.timer *.md; do
    [ -f "$f" ] || continue
    n=$(tr -cd '\r' < "$f" | wc -c)
    if [ "$n" -gt 0 ]; then
        sed -i 's/\r$//' "$f"
        m=$(tr -cd '\r' < "$f" | wc -c)
        echo "stripped $f ($n -> $m)"
    fi
done
echo "--- after: files still containing CR ---"
for f in *.sh *.service *.timer *.md; do
    [ -f "$f" ] || continue
    n=$(tr -cd '\r' < "$f" | wc -c)
    [ "$n" -gt 0 ] && echo "$f: $n CR"
done
echo "--- done ---"
