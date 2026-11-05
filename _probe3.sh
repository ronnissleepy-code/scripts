#!/bin/sh
# throwaway: local side of the CR/channel forensics
cd "$(dirname "$0")" || exit 1
echo LOCAL:
wc -c shodan.sh
printf 'quotes='
grep -c '"' shodan.sh
sh -n shodan.sh && echo SYNTAX_OK
md5sum shodan.sh
