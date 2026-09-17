"""KubePulse FastAPI application entrypoint."""

import logging
import time

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

from app.config import settings
from app.metrics import APP_INFO, HTTP_REQUEST_LATENCY_SECONDS, record_request
from app.routes.api import router

logging.basicConfig(
    level=getattr(logging, settings.log_level.upper(), logging.INFO),
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)
logger = logging.getLogger("kubepulse")

app = FastAPI(
    title="KubePulse",
    description="Kubernetes SRE & Reliability Platform demo service",
    version=settings.app_version,
)

APP_INFO.labels(version=settings.app_version).set(1)


@app.middleware("http")
async def metrics_middleware(request: Request, call_next):
    """Records request count, error count and latency for every request."""
    path = request.url.path
    method = request.method
    start = time.perf_counter()

    status_code = 500
    try:
        response = await call_next(request)
        status_code = response.status_code
        return response
    finally:
        duration = time.perf_counter() - start
        HTTP_REQUEST_LATENCY_SECONDS.labels(method=method, path=path).observe(duration)
        record_request(method, path, status_code)


@app.exception_handler(Exception)
async def unhandled_exception_handler(request: Request, exc: Exception):
    logger.exception("Unhandled exception while handling %s %s", request.method, request.url.path)
    return JSONResponse(status_code=500, content={"detail": "Internal server error"})


app.include_router(router)
