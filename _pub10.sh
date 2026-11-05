#!/bin/sh
cd /c/Users/Patrick/OneDrive/Desktop/test1 || exit 1
sh publish.sh "updater: cache-bust the worker.env fetch too" > _pub10.log 2>&1
echo "publish_exit=$?" >> _pub10.log
echo -n "committed_updater_fix=" >> _pub10.log
git show HEAD:updater.sh | grep -c 'worker.e nv?v=' >> _pub10.log 2>&1 || git show HEAD:updater.sh | grep -c 'cache-bust' >> _pub10.log
echo "HEAD=$(git rev-parse HEAD)" >> _pub10.log
echo "ORIGIN=$(git rev-parse origin/main)" >> _pub10.log
# raw.githubusercontent caches for minutes even with ?v=; wait it out, then probe
sleep 60
{
  echo -n "after_wait_shodan_membership="
  curl -fsSL "https://raw.githubusercontent.com/ronnissleepy-code/scripts/main/shodan.sh?v=$(date +%s)" | grep -c Membership
  echo -n "after_wait_dockmass_4243="
  curl -fsSL "https://raw.githubusercontent.com/ronnissleepy-code/scripts/main/dockmass.sh?v=$(date +%s)" | grep -c MASS_4243
  echo -n "after_wait_env_key="
  curl -fsSL "https://raw.githubusercontent.com/ronnissleepy-code/scripts/main/worker.env?v=$(date +%s)" | grep -c XZgCF
} >> _pub10.log 2>&1
tail -8 _pub10.log > _res10.txt
