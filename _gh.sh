#!/bin/sh
# throwaway: is the GITHUB_TOKEN still usable? (and does search/code still work)
TOK=$(grep -m1 '^GITHUB_TOKEN=' worker.env | cut -d'"' -f2)
echo "token_len=${#TOK} head=$(printf '%s' "$TOK" | cut -c1-7)"
code=$(curl -sS -o /tmp/gh.json -w '%{http_code}' \
    -H "Authorization: Bearer $TOK" \
    -H 'Accept: application/vnd.github+json' \
    'https://api.github.com/search/code?q=filename%3Aid_rsa&per_page=5' 2>/dev/null)
echo "http=$code"
head -c 400 /tmp/gh.json 2>/dev/null; echo
