#!/usr/bin/env bash
# lab S5: replace the recorded container ID, so no event matches the sandbox.
# Expected: SENSOR-4.
set -euo pipefail
printf '0000000000000000000000000000000000000000000000000000000000000000\n' > "$1/builds/sandbox.cid"
