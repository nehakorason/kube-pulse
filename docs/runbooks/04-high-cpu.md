# Runbook: High CPU Saturation

**Alert**: `KubePulseHighCPUSaturation` (CPU usage > 85% of limit for 5 minutes)

## Symptoms

- Grafana "CPU Utilisation" panel near/at the container CPU limit.
- Elevated latency, particularly on `/api/v1/work`.
- HPA may already be scaling (check "HPA Desired vs Current Replicas").

## Likely causes

- Genuine increase in traffic, especially to `/api/v1/work`.
- A client calling `/api/v1/work` with an unusually high `iterations` value.
- HPA at `maxReplicas` and still under-provisioned for current load.

## Initial checks

```bash
kubectl -n kubepulse top pods
kubectl -n kubepulse get hpa kubepulse
curl -s 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=sum(rate(kubepulse_cpu_work_duration_seconds_count[5m]))'
```

## Kubernetes commands

```bash
kubectl -n kubepulse get hpa kubepulse -w
kubectl -n kubepulse get deployment kubepulse -o jsonpath='{.spec.replicas}'
```

## Prometheus / Grafana checks

```
avg(rate(container_cpu_usage_seconds_total{namespace="kubepulse", container="kubepulse"}[5m]))
  / avg(kube_pod_container_resource_limits{namespace="kubepulse", container="kubepulse", resource="cpu"})
```
Compare against the HPA's 70% target (`k8s/hpa.yaml`) — if this metric is above 85% and the HPA is still below `maxReplicas`, expect it to keep scaling; if already at `maxReplicas`, this is a genuine capacity ceiling (see runbook 06).

## Mitigation

1. Let the HPA scale up (default behaviour); verify it is actually doing so (runbook 06 if not).
2. If `maxReplicas` is being hit repeatedly, raise it in `k8s/hpa.yaml` (and re-apply) after confirming node capacity allows it.
3. If caused by an abusive/unbounded `/api/v1/work?iterations=` request, note the endpoint already caps iterations at 20,000,000 via FastAPI's `Query(..., le=20_000_000)` — consider lowering this cap if still too expensive.

## Recovery verification

```bash
kubectl -n kubepulse get hpa kubepulse
```
Confirm CPU utilisation trends back toward the 70% target and, once load subsides, that replicas scale back down after the HPA's stabilization window (~120s, per `behavior.scaleDown` in `k8s/hpa.yaml`).

## Escalation considerations

- If CPU stays pinned at `maxReplicas` for an extended period, this is a capacity/cost decision (raise `maxReplicas` vs. reduce load) — escalate to the service owner.

## Post-incident checks

- Compare against `docs/experiments.md` Experiment 3 for expected CPU-saturation behaviour.
- Confirm resource requests/limits in `k8s/deployment.yaml` are still appropriate.
