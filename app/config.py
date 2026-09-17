"""Configuration for KubePulse, loaded from environment variables."""

import os
from dataclasses import dataclass


def _bool(name: str, default: bool) -> bool:
    val = os.getenv(name)
    if val is None:
        return default
    return val.strip().lower() in ("1", "true", "yes", "on")


@dataclass(frozen=True)
class Settings:
    app_name: str = os.getenv("APP_NAME", "kubepulse")
    app_version: str = os.getenv("APP_VERSION", "1.0.0")
    log_level: str = os.getenv("LOG_LEVEL", "INFO")
    port: int = int(os.getenv("PORT", "8000"))

    # /api/v1/slow default artificial delay range (seconds)
    slow_min_seconds: float = float(os.getenv("SLOW_MIN_SECONDS", "0.5"))
    slow_max_seconds: float = float(os.getenv("SLOW_MAX_SECONDS", "2.0"))

    # /api/v1/error controlled failure rate (0.0 - 1.0)
    error_rate: float = float(os.getenv("ERROR_RATE", "0.5"))

    # /api/v1/work CPU-bound workload default iterations
    work_default_iterations: int = int(os.getenv("WORK_DEFAULT_ITERATIONS", "2000000"))

    # readiness can be flipped to simulate a not-ready pod (failure injection)
    force_unready: bool = _bool("FORCE_UNREADY", False)
    # liveness can be flipped to simulate a hung/dead app (failure injection)
    force_unhealthy: bool = _bool("FORCE_UNHEALTHY", False)

    # simulated startup delay, exercised by the startup probe
    startup_delay_seconds: float = float(os.getenv("STARTUP_DELAY_SECONDS", "0"))


settings = Settings()
