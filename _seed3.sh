#!/bin/sh
cd /c/Users/Patrick/OneDrive/Desktop/test1 || exit 1
{
  echo "seed3 start $(date)"
  SEED_MAX=45 sh seed.sh run
  echo -n CREDITS_LEFT=
  curl -sS -m 15 "https://api.shodan.io/api-info?key=XZgCF4veHn1Y8mTTBcUC4yP11B7XPALE" \
    | grep -oE '"query_credits": *[0-9]+'
  sh seed.sh stat
  echo "seed3 done $(date)"
} > _seed3.log 2>&1
