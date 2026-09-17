#!/usr/bin/env bash
# Installs Python dependencies for local development.
set -euo pipefail

cd "$(dirname "$0")/.."

echo "==> Installing KubePulse dependencies"
python3 -m pip install --break-system-packages -r requirements-dev.txt

echo "==> Done. Try: make run   (or) uvicorn app.main:app --reload"
