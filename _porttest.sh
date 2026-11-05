#!/bin/sh
# functional check of the two new dock.sh bits, against the real local mass.found.
# run:  sh _porttest.sh
set -eu
PATH="/usr/bin:$PATH"; export PATH   # git-bash sh inherited a Windows PATH
cd "$(dirname "$0")"
WORK=.hunt
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
PORTMAP="$T/ports"
RAMFILE="$T/ram"

# --- 1. PORTMAP build (exactly the awk in dock.sh) ---------------------------
awk -F'@' 'NF>1 { split($1,a,"\t"); print a[1]"\t"$2 }' "$WORK/mass.found" 2>/dev/null \
    | sort -u > "$PORTMAP" || :
echo "portmap rows = $(wc -l < "$PORTMAP") (mass.found rows = $(wc -l < "$WORK/mass.found"))"
echo "--- portmap head ---"; head -3 "$PORTMAP" | cat -A | head -3

# --- 2. per-host port selection (the endpoint() logic) -----------------------
# verified host must use its recorded port; unknown host must be :2375 only
vip=$(head -1 "$PORTMAP" | cut -f2 >/dev/null; head -1 "$PORTMAP" | cut -f1)
want=$(grep -m1 "^$vip	" "$PORTMAP" | cut -f2)
for ip in "$vip" 203.0.113.9; do
    rp=$(grep -m1 "^$ip	" "$PORTMAP" 2>/dev/null | cut -f2)
    if [ -n "$rp" ]; then plist="$rp 2375 2376 4243"; else plist="2375"; fi
    echo "ip=$ip recorded_port=${rp:--} plist=[$plist]"
done
rp=$(grep -m1 "^$vip	" "$PORTMAP" | cut -f2)
[ "$rp" = "$want" ] && echo "PASS verified host resolves to its own port ($rp)" || { echo "FAIL port map"; exit 1; }
grep -q '^203.0.113.9	' "$PORTMAP" && { echo "FAIL unknown host matched"; exit 1; } || echo "PASS unknown host -> :2375 only"

# --- 3. ledger ordering: big hosts first (the re-arm awk in dock.sh) ---------
cut -f1 "$WORK/dock.owned" 2>/dev/null | sort -u > "$T/own" || :
grep -vxF -f "$T/own" "$WORK/dock.seen" 2>/dev/null | sort -u > "$T/lg" || :
first=$(head -1 "$T/lg")
printf '%s\t1000000\n10.0.0.7\t8000000000\n' "$first" > "$RAMFILE"
awk -F'\t' 'NR==FNR { m[$1]=$2; next } { print (($1 in m) ? m[$1] : 0) "\t" $1 }' \
    "$RAMFILE" "$T/lg" | sort -rn | cut -f2 > "$T/lg3"
echo "--- ledger: $(wc -l < "$T/lg") rows, sorted head ---"; head -5 "$T/lg3"
[ "$(head -1 "$T/lg3")" = "$first" ] && echo "PASS small-mem host sank below the 8GB host" \
    || { echo "FAIL ordering"; head -3 "$T/lg3"; exit 1; }
[ "$(wc -l < "$T/lg3")" = "$(wc -l < "$T/lg")" ] && echo "PASS no ledger rows lost" || { echo "FAIL row count"; exit 1; }
echo "ALL PASS"
