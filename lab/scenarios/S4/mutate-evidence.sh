#!/usr/bin/env bash
# lab S4: corrupt a line in the sensor log. Expected: SENSOR-2.
set -euo pipefail
printf 'this line is not valid json {\n' >> "$1/sensor/tetragon.log"
