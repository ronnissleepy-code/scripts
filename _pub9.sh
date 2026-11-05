#!/bin/sh
cd /c/Users/Patrick/OneDrive/Desktop/test1 || exit 1
sh publish.sh "shodan: wire OSS key + honest membership error; dockmass: probe legacy :4243" > _pub9.log 2>&1
echo "publish_exit=$?" >> _pub9.log
git rev-parse HEAD >> _pub9.log
git rev-parse origin/main >> _pub9.log
git --no-pager log --oneline -1 >> _pub9.log
git status --short | head -3 >> _pub9.log
tail -8 _pub9.log > _res9.txt
