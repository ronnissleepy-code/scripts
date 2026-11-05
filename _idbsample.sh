#!/bin/sh
# throwaway: does keyless Shodan already KNOW about :2375 hosts in cloud space?
# (that would make it a discovery channel, not just a filter). Samples addresses
# across the same /16s dockmass sweeps.
OUT=/tmp/idb.hits
: > "$OUT"
n=0; known=0; hits=0
for net in 5.9 88.198 64.227 159.89 146.190 138.201; do
    for h in 23 67 115 163 211; do
        for l in 5 77 199; do
            ip="$net.$h.$l"
            r=$(curl -sS -m 6 "https://internetdb.shodan.io/$ip" 2>/dev/null)
            n=$((n + 1))
            case "$r" in *'"detail"'*) ;; *) known=$((known + 1)) ;; esac
            case "$r" in
                *2375*|*8545*)
                    hits=$((hits + 1))
                    printf '%s\t%s\n' "$ip" "$(printf '%s' "$r" | head -c 200)" >> "$OUT" ;;
            esac
            sleep 0.3
        done
    done
done
echo "probed=$n known_in_db=$known interesting=$hits"
cat "$OUT"
