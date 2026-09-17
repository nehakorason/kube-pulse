#!/usr/bin/env bash
# Builds the image and deploys KubePulse to whatever cluster the current
# kubectl context points at (e.g. a local kind cluster).
set -euo pipefail
cd "$(dirname "$0")/.."

IMAGE="${IMAGE:-kubepulse:local}"
CLUSTER_NAME="${CLUSTER_NAME:-kubepulse}"

command -v kubectl >/dev/null 2>&1 || { echo "kubectl is required" >&2; exit 1; }

if command -v docker >/dev/null 2>&1; then
  echo "==> Building image $IMAGE"
  docker build -t "$IMAGE" .

  if command -v kind >/dev/null 2>&1 && kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    echo "==> Loading image into kind cluster '$CLUSTER_NAME'"
    kind load docker-image "$IMAGE" --name "$CLUSTER_NAME"
  fi
else
  echo "docker not found — skipping image build; assuming '$IMAGE' is already reachable by the cluster." >&2
fi

echo "==> Applying Kubernetes manifests"
kubectl apply -k k8s/

echo "==> Waiting for rollout"
kubectl rollout status deployment/kubepulse -n kubepulse --timeout=180s

echo "==> Deployed. Try:"
echo "    kubectl -n kubepulse port-forward svc/kubepulse 8000:80"
