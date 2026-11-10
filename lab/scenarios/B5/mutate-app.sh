#!/usr/bin/env bash
# lab B5: adds a larger dependency tree to stress event volume.
set -euo pipefail
source lab/lib.sh
add_dependency "$1" "lodash@4.17.21"
add_dependency "$1" "chalk@5.3.0"
add_dependency "$1" "commander@12.1.0"
