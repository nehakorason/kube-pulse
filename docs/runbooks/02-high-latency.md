# Runbook: High Latency

**Alert**: `KubePulseHighLatencyP95` (P95 latency > 1s for 5 minutes)

## Symptoms

- Grafana "Latency P95" / "Latency P99" panels elevated.
- Slower-than-normal responses reported by clients.

## Likely causes

- Traffic mix skewed toward `/api/v1/slow` or `/api/v1/work` (by design, these are the slowest endpoints).
- CPU saturation causing the event loop / worker to queue requests (see runbook 04).
- Too few replicas for current load (see whether HPA is scaling — runbook 06).
- A genuinely slow code path introduced in a recent deploy.

## Initial checks

```bash
curl -s 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=histogram_quantile(0.95, sum(rate(kubepulse_http_request_duration_seconds_bucket[5m])) by (le))'

# Per-endpoint P95 to isolate the source
curl -s 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=histogram_quantile(0.95, sum(rate(kubepulse_http_request_duration_seconds_bucket[5m])) by (le, path))'
```

## Kubernetes commands

```bash
kubectl -n kubepulse top pods
kubectl -n kubepulse get hpa kubepulse
kubectl -n kubepulse get pods -l app=kubepulse -o wide
```

## Prometheus / Grafana checks

- Compare "Request Rate" against "Latency P95" — if traffic rate is flat but latency climbs, suspect resource saturation, not load.
- Check "CPU Utilisation" and "HPA Desired vs Current Replicas" panels together.

## Mitigation

1. If saturation-driven, confirm HPA is scaling (`kubectl -n kubepulse get hpa kubepulse -w`); if capped at `maxReplicas`, consider raising `k8s/hpa.yaml`'s `maxReplicas`.
2. If traffic mix is the cause (heavy `/api/v1/slow` / `/api/v1/work` usage) and this is expected, this may be a false positive — consider whether the alert threshold or query should exclude those endpoints, and document the change in `docs/observability.md`.
3. If a regression, roll back:
   ```bash
   kubectl -n kubepulse rollout undo deployment/kubepulse
   ```

## Recovery verification

Re-query the P95 expression above and confirm it drops below 1s; watch the Grafana panel for at least one full 5-minute window before considering it resolved.

## Escalation considerations

- Sustained latency despite scaling to `maxReplicas` indicates a capacity planning issue — escalate to raise cluster/node capacity.

## Post-incident checks

- Re-run `scripts/load-test.sh` at the traffic level seen during the incident to confirm recovery under load, not just at rest.
- Update `docs/experiments.md` with any new data points.
