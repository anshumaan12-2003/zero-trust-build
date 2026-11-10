#!/usr/bin/env bash
# Sets up a cluster the same way everywhere: kind in CI, or k3s on the Azure VM.
# Installs monitoring, then Kyverno and the gate, then Argo CD, which deploys
# deploy/ from Git. Uses whatever cluster kubectl currently points at.
# Usage: cluster/install.sh <git branch or commit for Argo CD to deploy>
set -euo pipefail

REVISION="${1:?usage: cluster/install.sh <git branch or commit>}"
MONITORING_CHART="${MONITORING_CHART:-92.14.0}" # kube-prometheus-stack, 26 October 2026
KYVERNO_CHART="${KYVERNO_CHART:-3.9.2}"         # Kyverno v1.19.2, as in gate-test.yml
ARGOCD_CHART="${ARGOCD_CHART:-10.11.6}"         # Argo CD v3.5.6, 26 October 2026
UNSIGNED="ghcr.io/anshumaan12-2003/zero-trust-build-app:c482e9df61b4f6a1107fe809ef5f957360c287b5"

cd "$(dirname "$0")/.."

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts > /dev/null
helm repo add kyverno https://kyverno.github.io/kyverno/ > /dev/null
helm repo add argo https://argoproj.github.io/argo-helm > /dev/null
helm repo update > /dev/null

# Monitoring goes first, so the ServiceMonitor and PrometheusRule types exist.
echo "Installing kube-prometheus-stack $MONITORING_CHART"
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace --version "$MONITORING_CHART" \
  -f cluster/values/monitoring.yaml --wait --timeout 10m

echo "Installing Kyverno chart $KYVERNO_CHART"
helm upgrade --install kyverno kyverno/kyverno \
  --namespace kyverno --create-namespace --version "$KYVERNO_CHART" \
  -f cluster/values/kyverno.yaml --wait --timeout 5m

echo "Applying the gate"
kubectl apply -f gate/require-attestation.yaml
# The webhook takes a moment to start enforcing. Wait until it refuses the unsigned image.
for i in $(seq 1 30); do
  if ! kubectl run probe --image="$UNSIGNED" --restart=Never --dry-run=server -o name > /dev/null 2>&1; then
    echo "The gate is enforcing"
    break
  fi
  if [ "$i" = 30 ]; then
    echo "The gate never started refusing the unsigned image" >&2
    exit 1
  fi
  sleep 5
done

kubectl apply -f cluster/monitoring/alerts.yaml -f cluster/monitoring/dashboard.yaml

echo "Installing Argo CD chart $ARGOCD_CHART"
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd --create-namespace --version "$ARGOCD_CHART" \
  -f cluster/values/argocd.yaml --wait --timeout 10m

kubectl apply -f cluster/argocd/project.yaml
sed "s|REVISION|$REVISION|" cluster/argocd/app.yaml | kubectl apply -f -
echo "Argo CD now deploys deploy/ at $REVISION"
