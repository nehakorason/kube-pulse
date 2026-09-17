# Runbook: High Error Rate

**Alert**: `KubePulseHighErrorRate` (error rate > 5% for 2 minutes)

## Symptoms

- Grafana "Error Rate (%)" panel elevated.
- Clients report increased HTTP 500s.
- `kubepulse_http_errors_total` increasing faster than usual relative to `kubepulse_http_requests_total`.

## Likely causes

- `ERROR_RATE` environment variable / ConfigMap misconfigured to a non-zero value (e.g. left over from a failure-injection experiment).
- A recent deployment introduced a bug.
- A downstream dependency failure (if KubePulse is extended to call one).
- Resource exhaustion causing unhandled exceptions.

## Initial checks

```bash
# Current error rate over the last 5 minutes, via Prometheus API
curl -s 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=sum(rate(kubepulse_http_errors_total[5m])) / sum(rate(kubepulse_http_requests_total[5m]))'

# Recent pod logs
kubectl -n kubepulse logs -l app=kubepulse --tail=200
```

## Kubernetes commands

```bash
kubectl -n kubepulse get pods -l app=kubepulse
kubectl -n kubepulse describe deployment kubepulse
kubectl -n kubepulse get configmap kubepulse-config -o yaml
```

## Prometheus / Grafana checks

- Open the "KubePulse Overview" dashboard, check "Error Rate (%)" and "Request Rate" panels together — a rate spike with flat traffic suggests a code/config issue, not load.
- Query error breakdown by endpoint:
  ```
  sum by (path) (rate(kubepulse_http_errors_total[5m]))
  ```

## Mitigation

1. If `ERROR_RATE` was left non-zero from an experiment, reset it:
   ```bash
   kubectl -n kubepulse set env deployment/kubepulse ERROR_RATE=0.0
   ```
2. If caused by a recent deploy, roll back:
   ```bash
   kubectl -n kubepulse rollout undo deployment/kubepulse
   ```
3. If caused by resource exhaustion, check `kubectl top pods -n kubepulse` and consider raising limits in `k8s/deployment.yaml`.

## Recovery verification

```bash
kubectl -n kubepulse rollout status deployment/kubepulse
curl -s http://localhost:8000/api/v1/status
```
Confirm the Grafana error-rate panel returns below 5% and the alert clears in Prometheus (`/alerts`).

## Escalation considerations

- If error rate persists after rollback, this may indicate an infrastructure issue (node, network) rather than the application — escalate to on-call platform/infra owner.

## Post-incident checks

- Confirm `ERROR_RATE` / relevant ConfigMap values match intended defaults.
- Add a regression test under `tests/` if the root cause was a code defect.
- Update `docs/experiments.md` if thresholds needed adjustment.
