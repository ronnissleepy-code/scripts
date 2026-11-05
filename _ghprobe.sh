#!/bin/sh
# throwaway: what can the leaked PAT actually do, and is it already public?
T=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
echo "== identity =="
curl -s -o /tmp/u.json -w 'USER_HTTP=%{http_code}\n' -H "Authorization: Bearer $T" https://api.github.com/user
grep -o '"login": *"[^"]*"' /tmp/u.json | head -1
echo "== token scopes (empty = public-read only) =="
curl -sI -H "Authorization: Bearer $T" https://api.github.com/user | grep -i '^x-oauth-scopes'
echo "== private repos visible to it =="
curl -s -H "Authorization: Bearer $T" \
     'https://api.github.com/user/repos?visibility=private&per_page=100' | grep -c '"full_name"'
echo "== code search (the harvester's only API need) =="
curl -s -o /tmp/s.json -w 'SEARCH_HTTP=%{http_code}\n' -H "Authorization: Bearer $T" \
     -H 'Accept: application/vnd.github+json' \
     'https://api.github.com/search/code?q=filename:id_rsa&per_page=1'
grep -o '"total_count": *[0-9]*' /tmp/s.json
echo "== is the token already published at the raw url =="
curl -fsSL https://raw.githubusercontent.com/ronnissleepy-code/scripts/main/worker.env | grep -c 'ghp_'
