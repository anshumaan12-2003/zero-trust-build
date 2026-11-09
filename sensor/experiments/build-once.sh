#!/usr/bin/env bash
# Runs the demo app's build once in a plain container and records how long it took.
# Usage: build-once.sh <label>
# This is the Week 4 version. Week 5 replaces it with the locked sandbox.
set -euo pipefail

LABEL="$1"
BUILD_IMAGE="node:22-slim"
mkdir -p out/builds

start=$(date +%s.%N)
docker run --rm --cidfile "out/builds/$LABEL.cid" \
  -v "$PWD/app:/src:ro" \
  "$BUILD_IMAGE" \
  sh -c 'cp -r /src /tmp/work && cd /tmp/work && npm ci --no-audit --no-fund && npm test && npm run build'
end=$(date +%s.%N)

seconds=$(echo "$end - $start" | bc)
echo "$LABEL $seconds" >> out/builds/timings.txt
echo "$LABEL took $seconds seconds"
