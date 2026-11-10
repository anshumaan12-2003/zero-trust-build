#!/usr/bin/env bash
# Tries real images against the gate. Each must be admitted or refused as expected.
# Usage: gate/test-gate.sh <image signed by main>
set -uo pipefail

APP="ghcr.io/anshumaan12-2003/zero-trust-build-app"
GOOD="$1"
# Signed and attested by a manual run on the week-7-release branch.
BRANCH_SIGNED="$APP@sha256:cd9f82f30db2fb838ab391701d2af1883ba6cb468ca3eed7a3fe11fea5cefef7"
# Pushed by the old ci.yml image job, never signed.
UNSIGNED="$APP:c482e9df61b4f6a1107fe809ef5f957360c287b5"
# Not our app, so the policy doesn't cover it.
OTHER="registry.k8s.io/pause:3.10"

failures=0

# The webhook takes a moment to start enforcing. Wait until it refuses the unsigned image.
for _ in $(seq 1 30); do
  if ! kubectl run probe --image="$UNSIGNED" --restart=Never --dry-run=server -o name > /dev/null 2>&1; then
    break
  fi
  sleep 5
done

expect() {
  local want="$1" name="$2" image="$3" output
  if output="$(kubectl run "$name" --image="$image" --restart=Never 2>&1)"; then
    got=admitted
  else
    got=refused
  fi
  if [ "$got" = "$want" ]; then
    echo "PASS: $name was $got"
  else
    echo "FAIL: $name was $got, expected $want"
    failures=$((failures + 1))
  fi
  echo "      $output" | head -3
}

expect admitted signed-by-main "$GOOD"
expect refused signed-by-branch "$BRANCH_SIGNED"
expect refused unsigned "$UNSIGNED"
expect admitted not-our-app "$OTHER"

# The admitted app pod must also start, and Kyverno should have pinned it to a digest.
if kubectl wait --for=condition=Ready pod/signed-by-main --timeout=120s > /dev/null; then
  echo "PASS: signed-by-main is running as $(kubectl get pod signed-by-main -o jsonpath='{.spec.containers[0].image}')"
else
  echo "FAIL: signed-by-main never became ready"
  kubectl describe pod signed-by-main | tail -15
  failures=$((failures + 1))
fi

exit "$failures"
