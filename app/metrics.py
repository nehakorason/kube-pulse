"""Prometheus instrumentation for KubePulse."""

import time
from contextlib import contextmanager

from prometheus_client import (
    CONTENT_TYPE_LATEST,
    Counter,
    Gauge,
    Histogram,
    generate_latest,
)

# --- HTTP traffic / errors / latency (Golden Signals) ---------------------

HTTP_REQUESTS_TOTAL = Counter(
    "kubepulse_http_requests_total",
    "Total number of HTTP requests received",
    ["method", "path", "status"],
)

HTTP_ERRORS_TOTAL = Counter(
    "kubepulse_http_errors_total",
    "Total number of HTTP requests that resulted in an error (status >= 500)",
    ["method", "path", "status"],
)

HTTP_REQUEST_LATENCY_SECONDS = Histogram(
    "kubepulse_http_request_duration_seconds",
    "HTTP request latency in seconds",
    ["method", "path"],
    buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2, 5, 10),
)

# --- Application-level saturation / behaviour ------------------------------

CPU_WORK_DURATION_SECONDS = Histogram(
    "kubepulse_cpu_work_duration_seconds",
    "Duration of simulated CPU-bound work in seconds",
)

APP_READY = Gauge(
    "kubepulse_app_ready",
    "Whether the application currently reports itself ready (1) or not (0)",
)

APP_HEALTHY = Gauge(
    "kubepulse_app_healthy",
    "Whether the application currently reports itself healthy (1) or not (0)",
)

APP_INFO = Gauge(
    "kubepulse_app_info",
    "Static application build info",
    ["version"],
)


@contextmanager
def track_latency(method: str, path: str):
    start = time.perf_counter()
    try:
        yield
    finally:
        HTTP_REQUEST_LATENCY_SECONDS.labels(method=method, path=path).observe(time.perf_counter() - start)


def record_request(method: str, path: str, status: int) -> None:
    HTTP_REQUESTS_TOTAL.labels(method=method, path=path, status=str(status)).inc()
    if status >= 500:
        HTTP_ERRORS_TOTAL.labels(method=method, path=path, status=str(status)).inc()


def render_metrics() -> tuple[bytes, str]:
    return generate_latest(), CONTENT_TYPE_LATEST
