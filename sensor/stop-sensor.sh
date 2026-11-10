#!/usr/bin/env bash
# Records the end canary, stops Tetragon and makes the evidence readable.
set -uo pipefail

NONCE="$(cat out/nonce.txt)"
/bin/echo "ztb-canary-end-$NONCE" > /dev/null
sleep 3
# Lost events are blind spots. Save Tetragon's counters before it stops.
curl -fsS --max-time 10 http://127.0.0.1:2112/metrics > out/sensor/metrics.prom \
  || echo "Could not read Tetragon's metrics, so the judge can't rule out lost events." >&2
docker stop tetragon || echo "Tetragon had already stopped."
sudo chown -R "$(id -u):$(id -g)" out/
