def test_health_ok(client):
    resp = client.get("/health")
    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "healthy"
    assert "uptime_seconds" in body


def test_ready_ok(client):
    resp = client.get("/ready")
    assert resp.status_code == 200
    assert resp.json()["status"] == "ready"


def test_unhealthy_when_forced(monkeypatch, client_factory=None):
    import os
    import subprocess
    import sys

    # Run in a subprocess so the module-level Settings() picks up the env var.
    code = (
        "import sys; sys.path.insert(0, '.');"
        "from fastapi.testclient import TestClient;"
        "from app.main import app;"
        "c = TestClient(app);"
        "r = c.get('/health');"
        "print(r.status_code, r.json()['status'])"
    )
    env = os.environ.copy()
    env["FORCE_UNHEALTHY"] = "true"
    result = subprocess.run([sys.executable, "-c", code], env=env, capture_output=True, text=True, cwd=".")
    assert "503 unhealthy" in result.stdout, result.stdout + result.stderr


def test_unready_when_forced():
    import os
    import subprocess
    import sys

    code = (
        "import sys; sys.path.insert(0, '.');"
        "from fastapi.testclient import TestClient;"
        "from app.main import app;"
        "c = TestClient(app);"
        "r = c.get('/ready');"
        "print(r.status_code, r.json()['status'])"
    )
    env = os.environ.copy()
    env["FORCE_UNREADY"] = "true"
    result = subprocess.run([sys.executable, "-c", code], env=env, capture_output=True, text=True, cwd=".")
    assert "503 not_ready" in result.stdout, result.stdout + result.stderr
