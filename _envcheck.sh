#!/bin/sh
# throwaway: do we already have a Shodan / cloud API token anywhere on this PC?
echo "=== env vars of interest (values truncated) ==="
printenv | grep -iE 'shodan|censys|hcloud|digitalocean|doctl|linode|vultr|github|telegram' | while IFS= read -r l; do
    printf '%s\n' "$(printf '%s' "$l" | sed 's/\(.\{26\}\).*/\1.../')"
done
echo "=== token files ==="
for f in "$HOME/.shodan/api_key" "$HOME/.config/shodan/api_key" \
         "$HOME/.config/hcloud/cli.toml" "$HOME/.config/doctl/config.yaml" \
         "$HOME/.aws/credentials" "$HOME/.vultr-cli.yaml" "$HOME/.config/linode-cli" \
         "$HOME/.config/censys/config.json"; do
    [ -f "$f" ] && { echo "--- $f"; head -c 260 "$f"; echo; }
done
echo "=== kit worker.env credential lines (truncated) ==="
sed -n '/TOKEN\|SHODAN\|KEY_URL/p' /c/Users/Patrick/OneDrive/Desktop/test1/worker.env 2>/dev/null \
  | sed 's/\(ghp_.\{0,8\}\)[A-Za-z0-9]*/\1…/'
echo "=== done ==="
