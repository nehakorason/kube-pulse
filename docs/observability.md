# Observability

## Golden signals and where to find them

| Signal | Metric(s) | Dashboard panel | Alert |
|---|---|---|---|
| **Latency** | `kubepulse_http_request_duration_seconds` (histogram) | Latency P50 / P95 / P99 | `KubePulseHighLatencyP95` |
| **Traffic** | `kubepulse_http_requests_total` (counter) | Request Rate | — (informational) |
| **Errors** | `kubepulse_http_errors_total`, `kubepulse_http_requests_total` | Error Rate (%) | `KubePulseHighErrorRate` |
| **Saturation** | `container_cpu_usage_seconds_total`, `container_memory_working_set_bytes`, HPA metrics | CPU/Memory Utilisation, HPA Desired vs Current | `KubePulseHighCPUSaturation` |

## Application metrics (app/metrics.py)

- `kubepulse_http_requests_total{method,path,status}` — counter, every request.
- `kubepulse_http_errors_total{method,path,status}` — counter, requests with status >= 500.
- `kubepulse_http_request_duration_seconds{method,path}` — histogram, request latency; used to derive P50/P95/P99 via `histogram_quantile`.
- `kubepulse_cpu_work_duration_seconds` — histogram, time spent in the `/api/v1/work` CPU-bound handler.
- `kubepulse_app_ready` / `kubepulse_app_healthy` — gauges (0/1), mirror `/ready` and `/health` responses.
- `kubepulse_app_info{version}` — static build info gauge.

## Kubernetes / infrastructure metrics

Sourced from **kube-state-metrics** and **cAdvisor** (both scraped per
`monitoring/prometheus/prometheus-k8s.yml`):

- `kube_pod_container_status_restarts_total` — pod restart counts.
- `kube_deployment_status_replicas_available` / `kube_deployment_spec_replicas` — availability vs desired replicas.
- `kube_horizontalpodautoscaler_status_desired_replicas` / `..._current_replicas` — HPA behaviour.
- `container_cpu_usage_seconds_total`, `container_memory_working_set_bytes` — per-container CPU/memory usage.

## Alert thresholds and rationale

Defined in `monitoring/alerts/kubepulse-alerts.yml`.

| Alert | Threshold | Why this threshold |
|---|---|---|
| `KubePulseHighErrorRate` | error rate > 5% for 2m | 5% is a widely-used SRE default for a "this is clearly broken, not noise" error budget burn signal; 2 minutes filters out single-request blips while still catching real incidents quickly. |
| `KubePulseHighLatencyP95` | P95 > 1s for 5m | KubePulse's `/api/v1/slow` endpoint intentionally injects up to 2s of latency, so 1s is set above normal fast-path traffic (sub-100ms) but below the worst-case slow-path, catching genuine widespread degradation rather than expected slow-endpoint usage. 5 minutes avoids alerting on short bursts. |
| `KubePulseServiceUnavailable` | `up == 0` for 1m | Any scrape failure sustained for a full minute (i.e. several missed scrape intervals) indicates the target is genuinely unreachable, not a transient network blip. |
| `KubePulsePodRestartAnomaly` | >3 restarts in 15m | A single restart can be a normal deploy or transient issue; more than 3 within 15 minutes is a strong crash-loop signal. |
| `KubePulsePodUnavailable` | available < desired for 5m | Kubernetes' own rolling-update mechanics can transiently reduce available replicas; 5 minutes distinguishes a stuck/degraded deployment from a normal rollout. |
| `KubePulseHighCPUSaturation` | CPU usage > 85% of limit for 5m | 85% leaves headroom below the 100% throttling point while still being high enough to avoid false positives from normal load variance; by design this threshold sits below the HPA's 70% target utilisation trigger point, so this alert should mostly fire only when the HPA is already scaling and still can't keep up, or has hit `maxReplicas`. |

## Validating the observability stack

With `docker-compose up --build -d`:

1. **Prometheus is running**: `curl http://localhost:9090/-/healthy`
2. **Prometheus can scrape the application**: check `http://localhost:9090/targets` — the `kubepulse-app` job should show `state: up`.
3. **Application metrics appear**: `curl http://localhost:8000/metrics | grep kubepulse_http_requests_total`
4. **Grafana can access Prometheus**: Grafana → Connections → Data sources → Prometheus → "Test" should succeed (datasource is provisioned automatically from `monitoring/grafana/provisioning/datasources/datasource.yml`).
5. **Dashboard queries return data**: open the "KubePulse Overview" dashboard (auto-provisioned) after generating some traffic (`scripts/load-test.sh`).
6. **Alerts load successfully**: `curl http://localhost:9090/api/v1/rules` should list the `kubepulse-application` and `kubepulse-kubernetes` groups.
7. **Kubernetes metrics are available**: only applicable when deployed to a real cluster with kube-state-metrics installed — see `monitoring/prometheus/prometheus-k8s.yml`.

See the main README's "Environment limitations" section and `docs/experiments.md`
for exactly which of these were executed and verified during this project's
build, versus which require Docker/Kubernetes tooling not available in the
build environment.
