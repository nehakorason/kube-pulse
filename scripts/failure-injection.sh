#!/usr/bin/env bash
# Runs the three failure-injection experiments described in
# docs/experiments.md against a Kubernetes deployment of KubePulse:
#   A. Pod failure  (delete a pod, verify recreation + availability)
#   B. Application failure (raise error rate, verify alert condition + recovery)
#   C. CPU saturation (drive CPU load, observe HPA scale-up, then recovery)
#
# All experiments are safe and reversible. Requires kubectl pointed at a
# cluster with KubePulse already deployed (see scripts/deploy.sh).
set -euo pipefail
cd "$(dirname "$0")/.."

NAMESPACE="kubepulse"
command -v kubectl >/dev/null 2>&1 || { echo "kubectl is required" >&2; exit 1; }

section() { echo; echo "===== $1 ====="; }

section "Pre-check: deployment is healthy"
kubectl -n "$NAMESPACE" rollout status deployment/kubepulse --timeout=60s
kubectl -n "$NAMESPACE" get pods -l app=kubepulse

section "Experiment A: Pod failure"
POD=$(kubectl -n "$NAMESPACE" get pods -l app=kubepulse -o jsonpath='{.items[0].metadata.name}')
echo "Deleting pod: $POD"
START=$(date +%s)
kubectl -n "$NAMESPACE" delete pod "$POD"
echo "Waiting for a replacement pod to become Ready..."
kubectl -n "$NAMESPACE" wait --for=condition=Ready pod -l app=kubepulse --timeout=120s
END=$(date +%s)
echo "Recovery time: $((END - START))s"
kubectl -n "$NAMESPACE" get pods -l app=kubepulse

section "Experiment B: Application failure (elevated error rate)"
echo "Setting ERROR_RATE=1.0 to force application errors..."
kubectl -n "$NAMESPACE" set env deployment/kubepulse ERROR_RATE=1.0
kubectl -n "$NAMESPACE" rollout status deployment/kubepulse --timeout=120s
echo "Sample a few requests via port-forward (manual step if not already forwarded):"
echo "  kubectl -n $NAMESPACE port-forward svc/kubepulse 8000:80 &"
echo "  curl -s http://localhost:8000/api/v1/error"
echo "Reverting ERROR_RATE to 0.0..."
kubectl -n "$NAMESPACE" set env deployment/kubepulse ERROR_RATE=0.0
kubectl -n "$NAMESPACE" rollout status deployment/kubepulse --timeout=120s

section "Experiment C: CPU saturation / HPA"
echo "Baseline replica count:"
kubectl -n "$NAMESPACE" get hpa kubepulse
echo
echo "Generate load against /api/v1/work to drive CPU usage, e.g.:"
echo "  HOST=http://localhost:8000 USERS=50 DURATION=180s ./scripts/load-test.sh"
echo "Then watch scaling with:"
echo "  kubectl -n $NAMESPACE get hpa kubepulse -w"
echo "After load stops, confirm scale-down after the HPA's stabilization window."

section "Done"
echo "See docs/experiments.md for how to record and interpret results."
