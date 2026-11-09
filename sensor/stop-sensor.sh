#!/usr/bin/env bash
# Records the end canary, stops Tetragon and makes the evidence readable.
set -uo pipefail

NONCE="$(cat out/nonce.txt)"
/bin/echo "ztb-canary-end-$NONCE" > /dev/null
sleep 3
docker stop tetragon || echo "Tetragon had already stopped."
sudo chown -R "$(id -u):$(id -g)" out/
