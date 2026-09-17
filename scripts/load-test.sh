#!/usr/bin/env bash
# Runs a headless Locust load test against a target host (default:
# localhost:8000) and writes CSV results + a summary to load-testing/results.
set -euo pipefail
cd "$(dirname "$0")/.."

HOST="${HOST:-http://localhost:8000}"
USERS="${USERS:-20}"
SPAWN_RATE="${SPAWN_RATE:-5}"
DURATION="${DURATION:-60s}"
OUT_PREFIX="${OUT_PREFIX:-load-testing/results/run}"

command -v locust >/dev/null 2>&1 || { echo "locust is required (pip install -r requirements-dev.txt)" >&2; exit 1; }

echo "==> Checking target is reachable: $HOST/health"
curl -fsS "$HOST/health" >/dev/null || { echo "Target not reachable. Start the app first (make run / make docker-run / kubectl port-forward)." >&2; exit 1; }

mkdir -p "$(dirname "$OUT_PREFIX")"

echo "==> Running Locust: $USERS users, spawn rate $SPAWN_RATE, duration $DURATION against $HOST"
locust -f load-testing/locustfile.py \
  --host "$HOST" \
  --headless \
  -u "$USERS" \
  -r "$SPAWN_RATE" \
  -t "$DURATION" \
  --csv="$OUT_PREFIX" \
  --only-summary

echo "==> Results written to ${OUT_PREFIX}_stats.csv and ${OUT_PREFIX}_stats_history.csv"
