def test_root(client):
    resp = client.get("/")
    assert resp.status_code == 200
    body = resp.json()
    assert body["service"] == "kubepulse"


def test_status(client):
    resp = client.get("/api/v1/status")
    assert resp.status_code == 200
    body = resp.json()
    assert body["healthy"] is True
    assert body["ready"] is True


def test_metrics_endpoint_exposes_prometheus_format(client):
    client.get("/")  # generate at least one sample
    resp = client.get("/metrics")
    assert resp.status_code == 200
    assert "kubepulse_http_requests_total" in resp.text
    assert resp.headers["content-type"].startswith("text/plain")


def test_work_endpoint_runs_cpu_work(client):
    resp = client.get("/api/v1/work", params={"iterations": 5000})
    assert resp.status_code == 200
    body = resp.json()
    assert body["iterations"] == 5000
    assert body["duration_seconds"] >= 0


def test_work_endpoint_rejects_absurd_iterations(client):
    resp = client.get("/api/v1/work", params={"iterations": 999_999_999})
    assert resp.status_code == 422


def test_slow_endpoint_respects_bounds(client):
    resp = client.get("/api/v1/slow", params={"min_seconds": 0, "max_seconds": 0.05})
    assert resp.status_code == 200
    body = resp.json()
    assert 0 <= body["delayed_seconds"] <= 0.05 + 1e-6


def test_error_endpoint_always_fails_at_rate_one(client):
    resp = client.get("/api/v1/error", params={"rate": 1})
    assert resp.status_code == 500


def test_error_endpoint_never_fails_at_rate_zero(client):
    resp = client.get("/api/v1/error", params={"rate": 0})
    assert resp.status_code == 200
    assert resp.json() == {"status": "ok"}


def test_error_endpoint_increments_error_metric(client):
    client.get("/api/v1/error", params={"rate": 1})
    metrics = client.get("/metrics").text
    assert "kubepulse_http_errors_total" in metrics
