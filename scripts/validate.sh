#!/usr/bin/env bash
# Runs the full validation suite: lint, format, unit+integration tests,
# and static validation of YAML/JSON/HCL/Dockerfile artifacts.
# Automatically skips checks whose tooling isn't installed, clearly
# labelling them as skipped rather than pretending they passed.
set -uo pipefail
cd "$(dirname "$0")/.."

FAIL=0
pass() { echo "[PASS] $1"; }
fail() { echo "[FAIL] $1"; FAIL=1; }
skip() { echo "[SKIP - NOT EXECUTED, tool unavailable] $1"; }

echo "== KubePulse validation =="

echo "--- Lint (ruff) ---"
if command -v ruff >/dev/null 2>&1; then
  ruff check app tests && pass "ruff" || fail "ruff"
else
  skip "ruff not installed"
fi

echo "--- Format check (black) ---"
if command -v black >/dev/null 2>&1; then
  black --check app tests && pass "black" || fail "black"
else
  skip "black not installed"
fi

echo "--- Unit + integration tests (pytest) ---"
if command -v pytest >/dev/null 2>&1; then
  pytest tests/unit tests/integration -q && pass "pytest" || fail "pytest"
else
  skip "pytest not installed"
fi

echo "--- YAML / JSON validation ---"
python3 - <<'PYEOF'
import glob
import json
import sys
import yaml

ok = True
for f in sorted(set(
    glob.glob("k8s/*.yaml")
    + glob.glob("monitoring/**/*.yml", recursive=True)
    + glob.glob("monitoring/**/*.yaml", recursive=True)
    + [".github/workflows/ci.yml", ".github/workflows/cd.yml", "docker-compose.yml"]
)):
    try:
        list(yaml.safe_load_all(open(f)))
        print(f"[PASS] yaml: {f}")
    except Exception as exc:  # noqa: BLE001
        print(f"[FAIL] yaml: {f}: {exc}")
        ok = False

try:
    json.load(open("monitoring/grafana/dashboards/kubepulse-overview.json"))
    print("[PASS] json: monitoring/grafana/dashboards/kubepulse-overview.json")
except Exception as exc:  # noqa: BLE001
    print(f"[FAIL] json: dashboard: {exc}")
    ok = False

sys.exit(0 if ok else 1)
PYEOF
if [ $? -ne 0 ]; then FAIL=1; fi

echo "--- Dockerfile build ---"
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  if docker build -t kubepulse:validate . > /tmp/docker-build.log 2>&1; then
    pass "docker build (Dockerfile)"
  else
    echo "Production Dockerfile build failed (often means docker.io is unreachable in this network)."
    echo "See /tmp/docker-build.log for details."
    fail "docker build"
  fi
else
  skip "docker not installed or daemon not running"
fi

echo "--- kubectl manifest dry-run ---"
if command -v kubectl >/dev/null 2>&1; then
  kubectl apply --dry-run=client -k k8s/ && pass "kubectl dry-run" || fail "kubectl dry-run"
else
  skip "kubectl not installed"
fi

echo "--- terraform validate ---"
if command -v terraform >/dev/null 2>&1; then
  (cd terraform && terraform init -backend=false -input=false && terraform validate) \
    && pass "terraform validate" || fail "terraform validate"
else
  skip "terraform not installed"
fi

echo "=========================="
if [ "$FAIL" -eq 0 ]; then
  echo "Validation completed with no failures (see SKIP lines for anything not executable in this environment)."
else
  echo "Validation completed WITH FAILURES. See [FAIL] lines above."
fi
exit $FAIL
