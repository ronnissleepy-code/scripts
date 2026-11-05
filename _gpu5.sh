#!/bin/sh
# throwaway 5: the decisive GPU test, at CREATE time (needs no Cmd execution).
#
# Why create-time: the daemon validates HostConfig.DeviceRequests against its
# registered runtimes. With nvidia-container-toolkit installed it succeeds; with
# only runc registered it fails with "could not select device driver". So the
# create response answers "can a container reach a GPU here" even when the
# container's own command never reports back (which is what bit attempts 2-4).
H=134.209.121.89
echo "== verdict 1: DeviceRequests nvidia (this is what --gpus all sends)"
curl -sS -m 10 -X DELETE "http://$H:2375/containers/gpuq?force=1" >/dev/null 2>&1
curl -sS -m 25 -X POST "http://$H:2375/containers/create?name=gpuq" -H 'Content-Type: application/json' \
  -d '{"Image":"busybox:1.36","Cmd":["sh","-c","exit 0"],"HostConfig":{"DeviceRequests":[{"Driver":"nvidia","Count":-1,"Capabilities":[["gpu"]]}]}}' | head -c 320
echo
echo "== verdict 2: explicit nvidia runtime"
curl -sS -m 10 -X DELETE "http://$H:2375/containers/gpuq2?force=1" >/dev/null 2>&1
curl -sS -m 25 -X POST "http://$H:2375/containers/create?name=gpuq2" -H 'Content-Type: application/json' \
  -d '{"Image":"busybox:1.36","HostConfig":{"Runtime":"nvidia"}}' | head -c 320
echo
echo "== control: plain runtime (must succeed, else the test itself lies)"
curl -sS -m 10 -X DELETE "http://$H:2375/containers/gpuq3?force=1" >/dev/null 2>&1
curl -sS -m 25 -X POST "http://$H:2375/containers/create?name=gpuq3" -H 'Content-Type: application/json' \
  -d '{"Image":"busybox:1.36"}' | head -c 160
echo
echo "== images on that host (did the cuda pull stick)"
curl -sS -m 8 "http://$H:2375/images/json" 2>/dev/null | grep -o 'nvidia/cuda[^"]*' | head -3
echo "== runtimes summary"
grep -o '"Runtimes":{[^}]*}' /tmp/_i2.json | head -c 200; echo
date -u
