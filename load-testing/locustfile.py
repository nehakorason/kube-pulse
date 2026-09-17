"""KubePulse Locust load test.

Simulates realistic traffic against the KubePulse API: mostly lightweight
status/root requests, some CPU-bound work (for HPA/CPU-saturation
experiments), some artificially slow requests, and a smaller share of
requests that intentionally trigger errors.

Usage (headless example):
    locust -f load-testing/locustfile.py --host http://localhost:8000 \
        --headless -u 20 -r 5 -t 60s --csv=results/baseline
"""

from locust import HttpUser, between, task


class KubePulseUser(HttpUser):
    wait_time = between(0.2, 1.0)

    @task(10)
    def status(self):
        self.client.get("/api/v1/status", name="/api/v1/status")

    @task(10)
    def root(self):
        self.client.get("/", name="/")

    @task(3)
    def cpu_work(self):
        self.client.get(
            "/api/v1/work",
            params={"iterations": 200_000},
            name="/api/v1/work",
        )

    @task(3)
    def slow(self):
        self.client.get(
            "/api/v1/slow",
            params={"min_seconds": 0.1, "max_seconds": 0.5},
            name="/api/v1/slow",
        )

    @task(1)
    def error(self):
        with self.client.get(
            "/api/v1/error",
            params={"rate": 0.3},
            name="/api/v1/error",
            catch_response=True,
        ) as resp:
            # A 500 here is an intentionally simulated failure, not a
            # Locust-level failure, so mark expected 500s as success.
            if resp.status_code in (200, 500):
                resp.success()
