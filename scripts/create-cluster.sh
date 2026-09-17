#!/usr/bin/env bash
# Creates a local Kubernetes cluster with kind for running/validating
# KubePulse. Intended for a normal developer machine or CI runner with
# working internet access to Docker Hub / kind's node image registry.
#
# This exact flow (kind cluster + metrics-server + `kubectl apply -k k8s/`)
# has been validated end-to-end on a real Docker Desktop host — see
# docs/validation-report.md.
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-kubepulse}"

command -v kind >/dev/null 2>&1 || {
  echo "kind is required. Install: https://kind.sigs.k8s.io/docs/user/quick-start/#installation" >&2
  exit 1
}
command -v docker >/dev/null 2>&1 || {
  echo "Docker is required to run kind." >&2
  exit 1
}

if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
  echo "Cluster '${CLUSTER_NAME}' already exists. Skipping creation."
else
  echo "==> Creating kind cluster '${CLUSTER_NAME}'"
  kind create cluster --name "${CLUSTER_NAME}"
fi

echo "==> Cluster info"
kubectl cluster-info --context "kind-${CLUSTER_NAME}"

echo "==> Installing metrics-server (required for HPA)"
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
# Most local kind clusters don't have valid kubelet serving certs, so
# metrics-server needs to tolerate that:
kubectl patch deployment metrics-server -n kube-system --type=json \
  -p '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]' \
  || echo "metrics-server patch skipped (may already be applied)"

echo "==> Done. Next: docker build -t kube-pulse:local . && kind load docker-image kube-pulse:local --name ${CLUSTER_NAME} && kubectl apply -k k8s/"
