#!/usr/bin/env bash
# Runs the automated test suite.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> Unit tests"
pytest tests/unit -v

echo "==> Integration tests (spins up a real uvicorn process)"
pytest tests/integration -v
