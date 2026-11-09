#!/usr/bin/env bash
# Starts Tetragon on the runner and proves it can see events.
# POLICY_DIR picks which policies to load. It defaults to sensor/policies.
set -euo pipefail

TETRAGON_IMAGE="quay.io/cilium/tetragon:v1.8.0"
POLICY_DIR="${POLICY_DIR:-$PWD/sensor/policies}"

mkdir -p out/sensor
openssl rand -hex 16 > out/nonce.txt
NONCE="$(cat out/nonce.txt)"

docker run --name tetragon --rm -d \
  --pid=host --cgroupns=host --privileged \
  -v /sys/kernel/btf/vmlinux:/var/lib/tetragon/btf \
  -v "$POLICY_DIR:/etc/tetragon/tetragon.tp.d:ro" \
  -v "$PWD/out/sensor:/var/log/tetragon" \
  "$TETRAGON_IMAGE" \
  /usr/bin/tetragon \
  --export-filename /var/log/tetragon/tetragon.log \
  --export-file-max-size-mb 1024

# The canary is a harmless command that carries a secret random value.
# Seeing it in the log proves the sensor is recording.
for _ in $(seq 1 60); do
  /bin/echo "ztb-canary-start-$NONCE" > /dev/null
  if sudo grep -qs "ztb-canary-start-$NONCE" out/sensor/tetragon.log; then
    echo "Sensor is live."
    docker exec tetragon tetra tracingpolicy list || true
    exit 0
  fi
  sleep 1
done

echo "The sensor never saw the start canary." >&2
docker logs tetragon >&2 || true
exit 1
