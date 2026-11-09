#!/usr/bin/env bash
# Runs the untrusted build in a locked container with one way out: the proxy.
# APP_DIR picks the code to build. It defaults to app/.
set -euo pipefail

APP_DIR="${APP_DIR:-$PWD/app}"
BUILD_IMAGE="node:22-slim@sha256:5ec23b7c622b00547753bc6ffd78085dd868a68aeb41c8e0a1418f033e13d96d"
PROXY_IMAGE="ubuntu/squid:6.6-24.04_edge@sha256:8a3baed477e2c282ab8aa5edad442f69873246964f225c5c2ae8364b6610963c"

mkdir -p out/proxy out/dist out/builds
chmod 777 out/proxy out/dist

# The sandbox network has no route out. The proxy is on both networks.
docker network create --internal ztb-sandbox > /dev/null
docker network create ztb-egress > /dev/null

docker run -d --name ztb-proxy --network ztb-egress \
  -v "$PWD/sandbox/squid.conf:/etc/squid/squid.conf:ro" \
  -v "$PWD/sandbox/allowed-domains.txt:/etc/squid/allowed-domains.txt:ro" \
  -v "$PWD/out/proxy:/var/log/squid" \
  "$PROXY_IMAGE" > /dev/null
docker network connect ztb-sandbox ztb-proxy
docker inspect \
  -f '{{(index .NetworkSettings.Networks "ztb-sandbox").IPAddress}}' \
  ztb-proxy > out/proxy.ip
echo "Proxy is at $(cat out/proxy.ip)"

docker run --rm --name ztb-build \
  --cidfile out/builds/sandbox.cid \
  --network ztb-sandbox \
  --user 1000:1000 \
  --cap-drop=ALL \
  --security-opt no-new-privileges \
  --pids-limit 1024 \
  --memory 6g \
  -e HOME=/tmp/home \
  -e CI=true \
  -e npm_config_cache=/tmp/npm-cache \
  -e npm_config_proxy=http://ztb-proxy:3128 \
  -e npm_config_https_proxy=http://ztb-proxy:3128 \
  -v "$APP_DIR:/src:ro" \
  -v "$PWD/sandbox/build-steps.sh:/build-steps.sh:ro" \
  -v "$PWD/sandbox/decoys:/tmp/home:ro" \
  -v "$PWD/out/dist:/out" \
  "$BUILD_IMAGE" sh /build-steps.sh

docker stop ztb-proxy > /dev/null
tar -C out/dist -cf out/dist.tar .
sha256sum out/dist.tar > out/dist.sha256
echo "Build output: $(cut -c1-16 out/dist.sha256)..."
