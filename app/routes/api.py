"""Application API routes."""

import logging
import time

from fastapi import APIRouter, HTTPException, Query, Response

from app.config import settings
from app.metrics import APP_HEALTHY, APP_READY, CPU_WORK_DURATION_SECONDS, render_metrics
from app.services.workload import do_cpu_work, should_fail, simulate_latency

logger = logging.getLogger("kubepulse")
router = APIRouter()

_START_TIME = time.time()


@router.get("/")
def root():
    return {
        "service": settings.app_name,
        "version": settings.app_version,
        "message": "KubePulse Kubernetes SRE & Reliability Platform",
    }


@router.get("/health")
def health(response: Response):
    """Liveness probe target. Reports whether the process is healthy."""
    healthy = not settings.force_unhealthy
    APP_HEALTHY.set(1 if healthy else 0)
    if not healthy:
        response.status_code = 503
        return {"status": "unhealthy"}
    return {"status": "healthy", "uptime_seconds": round(time.time() - _START_TIME, 2)}


@router.get("/ready")
def ready(response: Response):
    """Readiness probe target. Reports whether the pod should receive traffic."""
    if settings.startup_delay_seconds and (time.time() - _START_TIME) < settings.startup_delay_seconds:
        APP_READY.set(0)
        response.status_code = 503
        return {"status": "not_ready", "reason": "starting_up"}

    is_ready = not settings.force_unready
    APP_READY.set(1 if is_ready else 0)
    if not is_ready:
        response.status_code = 503
        return {"status": "not_ready"}
    return {"status": "ready"}


@router.get("/metrics")
def metrics():
    payload, content_type = render_metrics()
    return Response(content=payload, media_type=content_type)


@router.get("/api/v1/status")
def status():
    return {
        "service": settings.app_name,
        "version": settings.app_version,
        "healthy": not settings.force_unhealthy,
        "ready": not settings.force_unready,
        "uptime_seconds": round(time.time() - _START_TIME, 2),
    }


@router.get("/api/v1/work")
def work(iterations: int = Query(default=None, ge=1, le=20_000_000)):
    """CPU-intensive endpoint used for CPU-saturation / HPA experiments."""
    n = iterations or settings.work_default_iterations
    start = time.perf_counter()
    done = do_cpu_work(n)
    duration = time.perf_counter() - start
    CPU_WORK_DURATION_SECONDS.observe(duration)
    return {"iterations": done, "duration_seconds": round(duration, 4)}


@router.get("/api/v1/slow")
def slow(
    min_seconds: float = Query(default=None, ge=0, le=30),
    max_seconds: float = Query(default=None, ge=0, le=30),
):
    """Endpoint with configurable artificial latency, for latency experiments."""
    delay = simulate_latency(min_seconds, max_seconds)
    return {"delayed_seconds": round(delay, 4)}


@router.get("/api/v1/error")
def error(rate: float = Query(default=None, ge=0, le=1)):
    """Endpoint with a controllable probability of returning a 500 error."""
    if should_fail(rate):
        logger.warning("Simulated application error triggered on /api/v1/error")
        raise HTTPException(status_code=500, detail="Simulated internal error")
    return {"status": "ok"}
