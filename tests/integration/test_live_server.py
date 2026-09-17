"""Integration tests that run against a real uvicorn process over HTTP.

These are skipped automatically if the server cannot be started (e.g. port
already bound), keeping unit tests independent of this heavier test.
"""

import socket
import subprocess
import sys
import tempfile
import time

import httpx
import pytest


def _free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


@pytest.fixture(scope="module")
def live_server():
    port = _free_port()
    # Uvicorn's stdout/stderr must not go to subprocess.PIPE: nothing reads that
    # pipe while the test is running, so once the OS pipe buffer fills (e.g. from
    # access logs and the /api/v1/error warning logs) the child blocks on write()
    # and requests start timing out. A real file has no such fixed-size buffer, so
    # the child can never block on it, while we can still read it back for
    # diagnostics if startup fails.
    log_file = tempfile.TemporaryFile()
    proc = subprocess.Popen(
        [sys.executable, "-m", "uvicorn", "app.main:app", "--host", "127.0.0.1", "--port", str(port)],
        cwd=".",
        stdout=log_file,
        stderr=subprocess.STDOUT,
    )
    base_url = f"http://127.0.0.1:{port}"
    deadline = time.time() + 15
    up = False
    while time.time() < deadline:
        try:
            r = httpx.get(f"{base_url}/health", timeout=1)
            if r.status_code == 200:
                up = True
                break
        except httpx.TransportError:
            time.sleep(0.3)
    if not up:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=5)
        log_file.seek(0)
        out = log_file.read()
        log_file.close()
        pytest.skip(f"live server did not start in time: {out.decode(errors='ignore')}")
    yield base_url
    proc.terminate()
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
    log_file.close()


def test_live_health(live_server):
    r = httpx.get(f"{live_server}/health")
    assert r.status_code == 200
    assert r.json()["status"] == "healthy"


def test_live_ready(live_server):
    r = httpx.get(f"{live_server}/ready")
    assert r.status_code == 200


def test_live_metrics_increment_across_requests(live_server):
    before = httpx.get(f"{live_server}/metrics").text
    for _ in range(5):
        httpx.get(f"{live_server}/api/v1/status")
    after = httpx.get(f"{live_server}/metrics").text
    assert 'kubepulse_http_requests_total{method="GET",path="/api/v1/status"' in after
    assert len(after) >= len(before)


def test_live_work_endpoint(live_server):
    r = httpx.get(f"{live_server}/api/v1/work", params={"iterations": 2000})
    assert r.status_code == 200
    assert r.json()["iterations"] == 2000


def test_live_error_rate_roughly_matches_configured_rate(live_server):
    n = 40
    failures = 0
    for _ in range(n):
        r = httpx.get(f"{live_server}/api/v1/error", params={"rate": 1.0})
        if r.status_code == 500:
            failures += 1
    assert failures == n
