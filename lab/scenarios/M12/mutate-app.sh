#!/usr/bin/env bash
set -euo pipefail
source lab/lib.sh
add_install_script "$1" "$SCENARIO_DIR/payload.js"
