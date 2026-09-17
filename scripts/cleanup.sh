#!/usr/bin/env bash
# Removes KubePulse Kubernetes resources and local generated artifacts.
set -uo pipefail
cd "$(dirname "$0")/.."

if command -v kubectl >/dev/null 2>&1; then
  echo "==> Deleting Kubernetes resources (if any)"
  kubectl delete -k k8s/ --ignore-not-found
fi

if command -v docker >/dev/null 2>&1; then
  echo "==> Stopping docker-compose stack (if running)"
  docker compose down -v --remove-orphans 2>/dev/null || true
fi

echo "==> Removing local caches and generated files"
find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
rm -rf .pytest_cache .ruff_cache htmlcov .coverage load-testing/results

echo "==> Cleanup complete"
