#!/bin/sh
cd /c/Users/Patrick/OneDrive/Desktop/test1 || exit 1
sh publish.sh "shodan: wire OSS key + honest membership error; dockmass: probe legacy :4243" > _pub8.log 2>&1
tail -n 12 _pub8.log
