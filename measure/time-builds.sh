#!/usr/bin/env bash
# Measures what the security checks add to a build.
# Usage: measure/time-builds.sh <runs> <output.csv>
#
# Method: plain and secured builds alternate, so a runner that slows down
# part-way affects both sides alike. Images are pulled first, so no run pays
# for a download.
#   plain    the same build steps in a plain container: default network,
#            root, no proxy, no sensor
#   secured  start the sensor, build in the sandbox through the proxy, stop
#            the sensor. Each part is timed on its own.
set -euo pipefail

RUNS="$1"
CSV="$2"
BUILD_IMAGE="node:22-slim@sha256:5ec23b7c622b00547753bc6ffd78085dd868a68aeb41c8e0a1418f033e13d96d"
PROXY_IMAGE="ubuntu/squid:6.6-24.04_edge@sha256:8a3baed477e2c282ab8aa5edad442f69873246964f225c5c2ae8364b6610963c"
TETRAGON_IMAGE="quay.io/cilium/tetragon:v1.8.0@sha256:5ed9088a1582131d71b06c98e0d549a37a71ae63ab13aabefc7a47553c822a9d"

for image in "$BUILD_IMAGE" "$PROXY_IMAGE" "$TETRAGON_IMAGE"; do
  docker pull -q "$image" > /dev/null
done

now() { date +%s.%N; }
since() { echo "$(now) - $1" | bc; }

clean_slate() {
  docker rm -f ztb-proxy ztb-build tetragon > /dev/null 2>&1 || true
  docker network rm ztb-sandbox ztb-egress > /dev/null 2>&1 || true
  sudo rm -rf out
}

echo "run,kind,part,seconds" > "$CSV"
for run in $(seq 1 "$RUNS"); do
  clean_slate
  start=$(now)
  docker run --rm -v "$PWD/app:/src:ro" "$BUILD_IMAGE" sh -c \
    'cp -r /src /tmp/work && cd /tmp/work && npm ci --no-audit --no-fund && npm test && npm run build && npm prune --omit=dev' \
    > /dev/null
  echo "$run,plain,build,$(since "$start")" >> "$CSV"

  clean_slate
  start=$(now)
  sensor/start-sensor.sh > /dev/null
  echo "$run,secured,sensor-start,$(since "$start")" >> "$CSV"
  start=$(now)
  sandbox/run-build.sh > /dev/null
  echo "$run,secured,build,$(since "$start")" >> "$CSV"
  start=$(now)
  sensor/stop-sensor.sh > /dev/null
  echo "$run,secured,sensor-stop,$(since "$start")" >> "$CSV"

  echo "run $run done"
done
clean_slate
cat "$CSV"
