#!/usr/bin/env bash
# Deletes the local kind cluster created by scripts/create-cluster.sh.
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-kubepulse}"

command -v kind >/dev/null 2>&1 || { echo "kind is required" >&2; exit 1; }

if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
  echo "==> Deleting kind cluster '${CLUSTER_NAME}'"
  kind delete cluster --name "${CLUSTER_NAME}"
else
  echo "Cluster '${CLUSTER_NAME}' does not exist. Nothing to do."
fi
