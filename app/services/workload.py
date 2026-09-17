"""Simulated workload helpers: CPU-bound work and artificial latency."""

import hashlib
import random
import time

from app.config import settings


def do_cpu_work(iterations: int) -> int:
    """Perform a deterministic, CPU-bound computation.

    Uses repeated SHA-256 hashing so it burns real CPU cycles (useful for
    HPA / CPU-saturation experiments) without any external dependency.
    Returns the number of iterations actually performed.
    """
    digest = b"kubepulse"
    for _ in range(iterations):
        digest = hashlib.sha256(digest).digest()
    return iterations


def simulate_latency(min_seconds: float | None = None, max_seconds: float | None = None) -> float:
    """Sleep for a random duration within the configured (or given) range."""
    lo = settings.slow_min_seconds if min_seconds is None else min_seconds
    hi = settings.slow_max_seconds if max_seconds is None else max_seconds
    if hi < lo:
        lo, hi = hi, lo
    delay = random.uniform(lo, hi)
    time.sleep(delay)
    return delay


def should_fail(error_rate: float | None = None) -> bool:
    rate = settings.error_rate if error_rate is None else error_rate
    rate = max(0.0, min(1.0, rate))
    return random.random() < rate
