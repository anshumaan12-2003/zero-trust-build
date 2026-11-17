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

# Every container counts, not just the main one.
refused() {
  local name="$1" output="$2"
  if [ "$3" = admitted ]; then
    echo "FAIL: $name was admitted"
    failures=$((failures + 1))
  else
    echo "PASS: $name was refused"
  fi
  echo "      $(echo "$output" | head -1 | cut -c1-200)"
}
init_pod="apiVersion: v1
kind: Pod
metadata:
  name: unsigned-init
spec:
  initContainers:
    - name: init
      image: $UNSIGNED
  containers:
    - name: main
      image: $OTHER"
if output="$(echo "$init_pod" | kubectl apply --dry-run=server -f - 2>&1)"; then got=admitted; else got=refused; fi
refused unsigned-init-container "$output" "$got"

kubectl run debug-host --image="$OTHER" --restart=Never > /dev/null
output="$(kubectl debug pod/debug-host --image="$UNSIGNED" --container=debugger 2>&1)"
# kubectl debug can print an error and still exit 0, so check the pod itself.
if kubectl get pod debug-host -o jsonpath='{.spec.ephemeralContainers[*].name}' | grep -q debugger; then
  got=admitted
else
  got=refused
fi
refused unsigned-ephemeral-container "$output" "$got"

# The allow-list: in an app namespace, only the signed app image by digest.
kubectl create namespace ztb-gate-test > /dev/null
kubectl label namespace ztb-gate-test ztb.dev/images=signed-app-only > /dev/null
kubectl apply -f gate/app-namespace-images.yaml > /dev/null
sleep 5
if kubectl run -n ztb-gate-test allowed-signed --image="$GOOD" --restart=Never --dry-run=server -o name > /dev/null 2>&1; then
  echo "PASS: allow-list: the signed image is admitted in the app namespace"
else
  echo "FAIL: allow-list: the signed image was refused in the app namespace"
  failures=$((failures + 1))
fi
if output="$(kubectl run -n ztb-gate-test other-image --image="$OTHER" --restart=Never --dry-run=server 2>&1)"; then got=admitted; else got=refused; fi
refused "allow-list: an image that isn't the app" "$output" "$got"

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

# 1. Checker crashed: no Kyverno pod running, but the deployment still wants
# one, so Kyverno doesn't treat it as a shutdown and its webhooks stay.
# failurePolicy: Fail must then refuse even the good image.
# (Changing the Service selector isn't enough: the API server keeps its open
# connection to the old pod, which a first version of this test missed.)
deployment=deployment/kyverno-admission-controller
old_pod="$(kubectl get pods -n kyverno -l app.kubernetes.io/component=admission-controller -o name)"
kubectl patch -n kyverno "$deployment" --type merge -p \
  '{"spec":{"strategy":{"type":"Recreate","rollingUpdate":null},"template":{"spec":{"nodeSelector":{"ztb-test/no-such-node":"true"}}}}}' > /dev/null
kubectl wait -n kyverno --for=delete "$old_pod" --timeout=90s > /dev/null
show_webhooks "with no Kyverno pod running"
if output="$(kubectl run checker-crashed --image="$GOOD" --restart=Never 2>&1)"; then
  echo "FAIL: checker-crashed: the image was admitted with no Kyverno pod running"
  failures=$((failures + 1))
else
  echo "PASS: checker-crashed: refused with no Kyverno pod running"
  echo "      $output" | cut -c1-220
fi
kubectl rollout undo -n kyverno "$deployment" > /dev/null
kubectl rollout status -n kyverno "$deployment" --timeout=180s > /dev/null

# 2. Checker switched off. Kyverno deletes its own webhooks when its deployment
# is scaled to 0 or deleted (IsGoingDown in pkg/utils/runtime/utils.go), so
# the gate opens. The guard (gate/guard-kyverno.yaml) refuses both.
kubectl apply -f gate/guard-kyverno.yaml > /dev/null
sleep 5
if output="$(kubectl scale -n kyverno deployment/kyverno-admission-controller --replicas=0 2>&1)"; then
  echo "FAIL: guard: Kyverno was scaled to 0"
  failures=$((failures + 1))
  kubectl scale -n kyverno deployment/kyverno-admission-controller --replicas=1 > /dev/null
  kubectl rollout status -n kyverno deployment/kyverno-admission-controller --timeout=180s > /dev/null
else
  echo "PASS: guard: scaling Kyverno to 0 was refused"
  echo "      $(echo "$output" | head -1 | cut -c1-200)"
fi
if kubectl delete -n kyverno deployment/kyverno-admission-controller --dry-run=server > /dev/null 2>&1; then
  echo "FAIL: guard: deleting Kyverno was allowed"
  failures=$((failures + 1))
else
  echo "PASS: guard: deleting Kyverno was refused"
fi

# A cluster admin can still remove the guard first. Then the gate opens for
# images outside the app namespaces. This known gap is asserted, so a change
# in Kyverno's behaviour gets noticed.
kubectl delete validatingadmissionpolicybinding ztb-guard-kyverno > /dev/null
sleep 5
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
# The allow-list is built into the API server, so it still holds in the app namespace.
if output="$(kubectl run -n ztb-gate-test checker-off-unsigned --image="$UNSIGNED" --restart=Never --dry-run=server 2>&1)"; then got=admitted; else got=refused; fi
refused "allow-list with Kyverno off: the unsigned app image" "$output" "$got"

exit "$failures"
