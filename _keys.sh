#!/bin/sh
# throwaway: which keys does the hunter actually use, and where do they come from?
W=/tmp/.sysd/.hunt/keys
echo "harvested key files on disk: $(ls "$W" 2>/dev/null | wc -l)"
echo "== names (owner_repo) =="
ls "$W" 2>/dev/null | head -30
echo "== type|bits|fingerprint|COMMENT (comment often names the host) =="
for k in $(ls "$W" 2>/dev/null | head -12); do
    printf '%s :: ' "$k"
    ssh-keygen -l -f "$W/$k" 2>/dev/null || echo "unreadable"
done
echo "== how hunt.sh obtains them =="
grep -n -e 'filename:id_rsa' -e 'keys/' -e 'PRIVATE KEY' /tmp/.sysd/hunt.sh | head -8
echo "== does hunt.sh ever use OUR id_key? =="
grep -n 'id_key' /tmp/.sysd/hunt.sh | head -5
echo "(no output above = hunt never uses id_key; spread.sh does)"
echo "== in-flight pairs =="
wc -l /tmp/.sysd/.hunt/pairs.txt 2>/dev/null
