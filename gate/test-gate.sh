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

# No real build with a failing verdict ever gets signed, so test the later
# checks by breaking the policy instead. Each broken copy must refuse the good image.
mutate() {
  local name="$1" from="$2" to="$3" message="$4" output
  sed "s|$from|$to|" gate/require-attestation.yaml | kubectl apply -f - > /dev/null
  sleep 5
  if output="$(kubectl run "$name" --image="$GOOD" --restart=Never --dry-run=server 2>&1)"; then
    echo "FAIL: $name: the good image was admitted"
    failures=$((failures + 1))
  elif [[ "$output" == *"$message"* ]]; then
    echo "PASS: $name: refused with \"$message\""
  else
    echo "FAIL: $name: refused for another reason: $output"
    failures=$((failures + 1))
  fi
}

mutate verdict-check "verdict == 'pass'" "verdict == 'not-a-verdict'" \
  "does not say pass"
mutate attestation-type "runtime-trace/v0.2" "runtime-trace/v9.9" \
  "no signed behaviour record"
kubectl apply -f gate/require-attestation.yaml > /dev/null

show_webhooks() {
  echo "      webhooks $1:"
  kubectl get validatingwebhookconfigurations \
    -o jsonpath='{range .items[*]}{.metadata.name}{" "}{range .webhooks[*]}[{.name} {.failurePolicy}]{end}{"\n"}{end}' \
    | grep -i kyverno | sed 's/^/        /'
}

# 1. Checker unreachable, as in a crash or network fault. Point Kyverno's
# Service at no pods. The webhooks stay registered, so failurePolicy: Fail
# must refuse even the good image.
selector="$(kubectl get service -n kyverno kyverno-svc -o jsonpath='{.spec.selector}')"
kubectl patch service -n kyverno kyverno-svc --type merge \
  -p '{"spec":{"selector":{"app.kubernetes.io/component":"nobody"}}}' > /dev/null
sleep 5
if output="$(kubectl run checker-unreachable --image="$GOOD" --restart=Never 2>&1)"; then
  echo "FAIL: checker-unreachable: the image was admitted while Kyverno couldn't be reached"
  failures=$((failures + 1))
else
  echo "PASS: checker-unreachable: refused while Kyverno couldn't be reached"
  echo "      $output" | cut -c1-200
fi
kubectl patch service -n kyverno kyverno-svc --type merge -p "{\"spec\":{\"selector\":$selector}}" > /dev/null

# 2. Checker switched off. Kyverno deletes its own webhooks when its deployment
# is scaled to 0 or deleted (IsGoingDown in pkg/utils/runtime/utils.go), so
# the gate opens. This is a known gap. The test asserts it so a change in
# Kyverno's behaviour gets noticed.
show_webhooks "before scaling Kyverno to 0"
kubectl scale -n kyverno deployment/kyverno-admission-controller --replicas=0 > /dev/null
kubectl wait -n kyverno --for=delete pod -l app.kubernetes.io/component=admission-controller --timeout=90s > /dev/null
show_webhooks "after scaling Kyverno to 0"
if kubectl run checker-off --image="$GOOD" --restart=Never > /dev/null 2>&1; then
  echo "KNOWN GAP: checker-off: admitted, because Kyverno removed its webhooks"
else
  echo "FAIL: checker-off: refused, so Kyverno's shutdown behaviour changed. Update docs/week8-gate-results.md"
  failures=$((failures + 1))
fi

exit "$failures"
