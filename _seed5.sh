#!/bin/sh
cd /c/Users/Patrick/OneDrive/Desktop/test1 || exit 1
{
  echo "seed5 start $(date)"
  SEED_MAX=40 sh seed.sh run 40
  echo -n CREDITS_LEFT=
  curl -sS -m 15 "https://api.shodan.io/api-info?key=XZgCF4veHn1Y8mTTBcUC4yP11B7XPALE" |
      tr ',' '\n' | grep -e query_credits -e scan_credits | head -4
  echo "seed5 done $(date)"
} > _seed5.log 2>&1
