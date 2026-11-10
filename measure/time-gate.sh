#!/usr/bin/env bash
# Measures how long the gate adds to creating a pod.
# Usage: measure/time-gate.sh <image signed by main> <runs> <output.csv>
# Needs a cluster with Kyverno installed and the gate not yet applied.
#
# Method: server-side dry runs, so admission runs in full but nothing is
# scheduled. First without any image policy, then with gate/require-attestation.yaml.
# The first gated call is cold (no cached verification); later ones may be
# served from Kyverno's cache, so both are reported.
set -euo pipefail

GOOD="$1"
RUNS="$2"
CSV="$3"

now() { date +%s.%N; }

time_create() {
  local kind="$1" run="$2" start
  start=$(now)
  kubectl run "t-$kind-$run" --image="$GOOD" --restart=Never --dry-run=server -o name > /dev/null
  echo "$run,$kind,$(echo "$(now) - $start" | bc)" >> "$CSV"
}

echo "run,kind,seconds" > "$CSV"
for run in $(seq 1 "$RUNS"); do time_create no-policy "$run"; done

kubectl apply -f gate/require-attestation.yaml > /dev/null
# Wait until the gate enforces: an unsigned image must be refused.
UNSIGNED="ghcr.io/anshumaan12-2003/zero-trust-build-app:c482e9df61b4f6a1107fe809ef5f957360c287b5"
for _ in $(seq 1 30); do
  if ! kubectl run probe --image="$UNSIGNED" --restart=Never --dry-run=server -o name > /dev/null 2>&1; then
    break
  fi
  sleep 5
done

for run in $(seq 1 "$RUNS"); do time_create gated "$run"; done
cat "$CSV"
