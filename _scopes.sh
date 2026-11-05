#!/bin/sh
# throwaway: can this token actually push, or is it read-only?
TOK=$(grep -m1 '^GITHUB_TOKEN=' worker.env | cut -d'"' -f2)
echo "-- token scopes (x-oauth-scopes):"
curl -sS -D - -o /dev/null -H "Authorization: Bearer $TOK" https://api.github.com/user 2>/dev/null | grep -i '^x-oauth-scopes'
echo "-- viewer login:"
curl -sS -H "Authorization: Bearer $TOK" https://api.github.com/user 2>/dev/null | tr ',' '\n' | grep '"login"'
echo "-- repo permissions:"
curl -sS -H "Authorization: Bearer $TOK" https://api.github.com/repos/ronnissleepy-code/scripts 2>/dev/null | tr ',' '\n' | grep -i -A1 'permissions'
