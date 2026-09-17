# Runbook: Service Unavailable

**Alerts**: `KubePulseServiceUnavailable` (`up == 0` for 1m), `KubePulsePodUnavailable` (available < desired replicas for 5m)

## Symptoms

- Clients cannot reach the service (connection refused/timeouts).
- Prometheus target for `kubepulse-app` shows `state: down`.
- `kubectl get pods -n kubepulse` shows 0 Ready pods, or the Service has no endpoints.

## Likely causes

- All pods failing readiness (e.g. `FORCE_UNREADY=true` left set).
- All pods crash-looping (see runbook 03).
- Deployment scaled to 0, or a bad rollout stuck with `maxUnavailable: 0` blocking progress.
- Service selector mismatch after a manifest change.

## Initial checks

```bash
kubectl -n kubepulse get pods -l app=kubepulse
kubectl -n kubepulse get endpoints kubepulse
kubectl -n kubepulse get deployment kubepulse -o wide
```

## Kubernetes commands

```bash
kubectl -n kubepulse describe deployment kubepulse
kubectl -n kubepulse rollout status deployment/kubepulse
kubectl -n kubepulse get events --sort-by=.lastTimestamp | tail -30
```

## Prometheus / Grafana checks

```
up{job=~"kubepulse.*"}
kube_deployment_status_replicas_available{namespace="kubepulse", deployment="kubepulse"}
```
Both should be 1 / equal to desired replicas respectively when healthy.

## Mitigation

1. If `FORCE_UNREADY`/`FORCE_UNHEALTHY` were left set from an experiment, reset them:
   ```bash
   kubectl -n kubepulse set env deployment/kubepulse FORCE_UNREADY=false FORCE_UNHEALTHY=false
   ```
2. If the Deployment was scaled to 0:
   ```bash
   kubectl -n kubepulse scale deployment/kubepulse --replicas=2
   ```
3. If a bad rollout is stuck, roll back:
   ```bash
   kubectl -n kubepulse rollout undo deployment/kubepulse
   ```
4. If the Service has no endpoints despite Ready pods, verify label selectors match between `k8s/service.yaml` and `k8s/deployment.yaml` (`app: kubepulse` on both).

## Recovery verification

```bash
kubectl -n kubepulse get endpoints kubepulse
curl -s http://localhost:8000/health
```
Confirm the Service has at least one endpoint and `/health` returns 200.

## Escalation considerations

- If pods are Ready but the Service still has no traffic reaching it, this may be a CNI/networking issue — escalate to cluster/networking owner.

## Post-incident checks

- Confirm `kubectl -n kubepulse get hpa kubepulse` shows current replicas within `[minReplicas, maxReplicas]`.
- Re-run `scripts/failure-injection.sh` Experiment A to confirm normal pod-failure recovery still works.
