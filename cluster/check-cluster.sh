#!/usr/bin/env bash
# Checks a cluster set up by cluster/install.sh: Argo CD deployed the signed
# app, the gate refuses an unsigned image (directly and through Git), the
# dashboard has data, and an alert fires when Kyverno is switched off.
# Usage: cluster/check-cluster.sh <the revision install.sh was given>
set -uo pipefail

REVISION="${1:?usage: cluster/check-cluster.sh <git branch or commit>}"
GOOD="$(cat "$(dirname "$0")/../gate/good-image.txt")"
UNSIGNED="ghcr.io/anshumaan12-2003/zero-trust-build-app:c482e9df61b4f6a1107fe809ef5f957360c287b5"
cd "$(dirname "$0")/.." || exit 1

failures=0
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; failures=$((failures + 1)); }

forwards=()
trap 'kill "${forwards[@]}" 2> /dev/null' EXIT
forward() {
  kubectl port-forward -n "$1" "$2" "$3" > /dev/null 2>&1 &
  forwards+=("$!")
}

# 1. Argo CD deployed deploy/ and the gate let its pods in.
if kubectl wait -n argocd application/ztb-app --for=jsonpath='{.status.sync.status}'=Synced --timeout=300s > /dev/null \
  && kubectl wait -n argocd application/ztb-app --for=jsonpath='{.status.health.status}'=Healthy --timeout=300s > /dev/null; then
  pass "Argo CD synced deploy/ at $REVISION and the app is healthy"
else
  fail "Argo CD didn't sync a healthy app"
  kubectl get application -n argocd ztb-app -o jsonpath='{.status.conditions}{"\n"}{.status.operationState.message}{"\n"}'
fi
kubectl get pods -n ztb -o custom-columns='POD:.metadata.name,READY:.status.containerStatuses[0].ready,IMAGE:.spec.containers[0].image'
ready="$(kubectl get deployment -n ztb ztb-app -o jsonpath='{.status.readyReplicas}')"
if [ "${ready:-0}" -ge 2 ]; then
  pass "both app pods are ready"
else
  fail "only ${ready:-0} of 2 app pods are ready"
fi

# 2. The gate decides the same way it did on kind in Week 8.
if kubectl run direct-signed --image="$GOOD" --restart=Never --dry-run=server -o name > /dev/null 2>&1; then
  pass "the signed image is admitted"
else
  fail "the signed image was refused"
fi
if output="$(kubectl run direct-unsigned --image="$UNSIGNED" --restart=Never --dry-run=server 2>&1)"; then
  fail "the unsigned image was admitted"
else
  pass "the unsigned image is refused: $(echo "$output" | cut -c1-160)"
fi

# 3. Git asks for the unsigned image. Argo CD applies the Deployment, but
# the gate refuses every pod its ReplicaSet tries to create.
sed "s|REVISION|$REVISION|" cluster/argocd/bad-app.yaml | kubectl apply -f - > /dev/null
refusal=""
for _ in $(seq 1 36); do
  refusal="$(kubectl get events -n ztb-bad --field-selector reason=FailedCreate -o jsonpath='{.items[*].message}' 2> /dev/null)"
  [[ "$refusal" == *"not signed by pipeline.yml"* ]] && break
  sleep 5
done
running="$(kubectl get pods -n ztb-bad -o name 2> /dev/null | wc -l | tr -d ' ')"
if [[ "$refusal" == *"not signed by pipeline.yml"* ]] && [ "$running" = 0 ]; then
  pass "Argo CD applied the unsigned Deployment and the gate refused its pods"
  echo "      $(echo "$refusal" | head -c 220)"
else
  fail "the unsigned Deployment wasn't refused as expected ($running pods, events: ${refusal:-none})"
fi
kubectl get application -n argocd ztb-bad -o jsonpath='      Argo CD says: sync {.status.sync.status}, health {.status.health.status}{"\n"}'

# 4. Prometheus has scraped the decisions, and every dashboard panel has data.
forward monitoring svc/kube-prometheus-stack-prometheus 9090:9090
prom=http://127.0.0.1:9090
sleep 3
echo "Kyverno scrape targets:"
curl -fsS "$prom/api/v1/query" --data-urlencode 'query=up{namespace="kyverno"}' \
  | python3 -c 'import json,sys; [print("      ", r["metric"].get("service"), r["metric"].get("job"), r["value"][1]) for r in json.load(sys.stdin)["data"]["result"]]'
echo "Gate results Kyverno reported:"
curl -fsS "$prom/api/v1/query" --data-urlencode 'query=kyverno_image_validating_policy_results_total' \
  | python3 -c 'import json,sys; [print("      ", {k: v for k, v in r["metric"].items() if k in ("policy_name","result","resource_namespace","resource_request_operation","execution_cause")}, r["value"][1]) for r in json.load(sys.stdin)["data"]["result"]]'
# How much memory each part uses, to size the Azure VM.
echo "Memory in use by namespace (MiB):"
curl -fsS "$prom/api/v1/query" --data-urlencode 'query=sum by (namespace) (container_memory_working_set_bytes{container!=""}) / 1048576' \
  | python3 -c 'import json,sys; [print("       %s: %.0f" % (r["metric"].get("namespace"), float(r["value"][1]))) for r in sorted(json.load(sys.stdin)["data"]["result"], key=lambda r: -float(r["value"][1]))]'
panels="$(mktemp)"
dashboard_ok=1
for _ in $(seq 1 12); do
  if python3 cluster/check-metrics.py "$prom" cluster/monitoring/dashboard.yaml > "$panels" 2>&1; then
    dashboard_ok=0
    break
  fi
  sleep 10
done
sed 's/^/      /' "$panels"
if [ "$dashboard_ok" = 0 ]; then
  pass "every gate panel on the dashboard has data"
else
  fail "some dashboard panels are empty"
fi

# 5. Grafana loaded the dashboard.
forward monitoring svc/kube-prometheus-stack-grafana 3000:80
sleep 3
password="$(kubectl get secret -n monitoring kube-prometheus-stack-grafana -o jsonpath='{.data.admin-password}' | base64 -d)"
found="$(curl -fsS -u "admin:$password" 'http://127.0.0.1:3000/api/search?query=Zero%20Trust' 2> /dev/null)"
if [[ "$found" == *'"uid":"ztb-gate"'* ]]; then
  pass "Grafana loaded the gate dashboard"
else
  fail "Grafana has no gate dashboard: ${found:-no answer}"
fi

alert_state() {
  curl -fsS "$prom/api/v1/alerts" | python3 -c "import json,sys; print(' '.join(sorted({a['state'] for a in json.load(sys.stdin)['data']['alerts'] if a['labels']['alertname'] == '$1'})) or 'inactive')"
}
state="$(alert_state ZTBUnprovenImageRefused)"
if [ "$state" = firing ]; then
  pass "ZTBUnprovenImageRefused is firing after the refusals"
else
  fail "ZTBUnprovenImageRefused is $state"
fi

# 6. Switch the checker off, the known gap from Week 8. The gate opens, so an alert must fire.
kubectl scale -n kyverno deployment/kyverno-admission-controller --replicas=0 > /dev/null
start=$SECONDS
state=inactive
while [ $((SECONDS - start)) -lt 240 ]; do
  state="$(alert_state ZTBGateDown)"
  [ "$state" = firing ] && break
  sleep 10
done
if [ "$state" = firing ]; then
  pass "ZTBGateDown fired $((SECONDS - start)) s after Kyverno was scaled to 0"
else
  fail "ZTBGateDown is $state $((SECONDS - start)) s after Kyverno was scaled to 0"
fi
kubectl scale -n kyverno deployment/kyverno-admission-controller --replicas=1 > /dev/null

exit "$failures"
