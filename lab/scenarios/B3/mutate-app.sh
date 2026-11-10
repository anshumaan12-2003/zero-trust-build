#!/usr/bin/env bash
# lab B3: adds a new ordinary dependency. Exercises the unknown-program rule,
# which is a PROC-2 warning while unknown_action is "warn".
set -euo pipefail
source lab/lib.sh
add_dependency "$1" "is-odd@3.0.1"
