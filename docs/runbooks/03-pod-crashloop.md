# Runbook: Pod CrashLoopBackOff / Restart Anomaly

**Alert**: `KubePulsePodRestartAnomaly` (>3 restarts in 15 minutes)

## Symptoms

- `kubectl get pods -n kubepulse` shows `CrashLoopBackOff` or a high `RESTARTS` count.
- Grafana "Pod Restarts" panel spikes.

## Likely causes

- Liveness probe (`/health`) failing repeatedly, e.g. due to `FORCE_UNHEALTHY=true` left set from a failure-injection experiment.
- Application crashing on startup (bad config, missing dependency).
- Out-of-memory kill (OOMKilled) if traffic/work exceeds the memory limit.

## Initial checks

```bash
kubectl -n kubepulse get pods -l app=kubepulse
kubectl -n kubepulse describe pod <pod-name>   # check "Last State" and "Reason"
kubectl -n kubepulse logs <pod-name> --previous
```

## Kubernetes commands

```bash
# Confirm the reason for the most recent restart
kubectl -n kubepulse get pod <pod-name> -o jsonpath='{.status.containerStatuses[0].lastState}'

# Check current ConfigMap values (e.g. accidental FORCE_UNHEALTHY=true)
kubectl -n kubepulse get configmap kubepulse-config -o yaml
```

## Prometheus / Grafana checks

```
increase(kube_pod_container_status_restarts_total{namespace="kubepulse"}[15m])
```
Check whether restarts are isolated to one pod (node-specific issue) or all pods (config/image issue).

## Mitigation

1. If `FORCE_UNHEALTHY` was left set:
   ```bash
   kubectl -n kubepulse set env deployment/kubepulse FORCE_UNHEALTHY=false
   ```
2. If OOMKilled, raise `resources.limits.memory` in `k8s/deployment.yaml` and re-apply.
3. If a bad image/config was deployed, roll back:
   ```bash
   kubectl -n kubepulse rollout undo deployment/kubepulse
   ```

## Recovery verification

```bash
kubectl -n kubepulse get pods -l app=kubepulse -w
```
Confirm `RESTARTS` stops increasing and pods remain `Running`/`Ready` for several minutes.

## Escalation considerations

- Restarts isolated to pods on a single node may indicate node-level issues (disk pressure, kernel) — escalate to infra/platform team, consider cordoning the node.

## Post-incident checks

- Confirm no failure-injection environment variables (`FORCE_UNHEALTHY`, `FORCE_UNREADY`) are still set in the live ConfigMap.
- Review resource requests/limits against observed usage (`kubectl top pods`).
