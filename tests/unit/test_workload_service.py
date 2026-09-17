import time

from app.services.workload import do_cpu_work, should_fail, simulate_latency


def test_do_cpu_work_returns_iteration_count():
    assert do_cpu_work(1000) == 1000


def test_simulate_latency_sleeps_within_bounds():
    start = time.perf_counter()
    delay = simulate_latency(min_seconds=0.01, max_seconds=0.03)
    elapsed = time.perf_counter() - start
    assert 0.01 <= delay <= 0.03
    assert elapsed >= 0.01


def test_should_fail_rate_zero_never_fails():
    assert all(should_fail(0.0) is False for _ in range(50))


def test_should_fail_rate_one_always_fails():
    assert all(should_fail(1.0) is True for _ in range(50))
