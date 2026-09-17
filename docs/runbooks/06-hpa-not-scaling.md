# Runbook: HPA Not Scaling

**Symptom trigger**: CPU/memory utilisation is clearly above target (see runbook 04) but `kubectl get hpa` shows no replica increase.

## Symptoms

- `kubectl -n kubepulse get hpa kubepulse` shows `<unknown>` under `TARGETS`, or a stable replica count despite high load.
- `KubePulseHighCPUSaturation` firing without a corresponding increase in `kube_horizontalpodautoscaler_status_current_replicas`.

## Likely causes

- **metrics-server not installed** in the cluster (most common cause in a fresh local kind/minikube cluster).
- Resource **requests** not set on the container (HPA needs `resources.requests.cpu` to compute utilisation percentage — already set in `k8s/deployment.yaml`, but verify after any manual edits).
- HPA already at `maxReplicas`.
- Recent scale event still inside the `behavior.scaleUp.stabilizationWindowSeconds` (30s) window.

## Initial checks

```bash
kubectl get deployment metrics-server -n kube-system
kubectl -n kubepulse describe hpa kubepulse
kubectl top pods -n kubepulse
```

If `kubectl top pods` fails with a "metrics not available" error, metrics-server is the issue.

## Kubernetes commands

```bash
# Install metrics-server on a local kind cluster (requires --kubelet-insecure-tls
# for most local clusters, since they don't have valid kubelet certs):
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl patch deployment metrics-server -n kube-system --type=json \
  -p '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
```

## Prometheus / Grafana checks

```
kube_horizontalpodautoscaler_status_current_replicas{namespace="kubepulse"}
kube_horizontalpodautoscaler_status_desired_replicas{namespace="kubepulse"}
```
If `desired > current` and stays that way for more than the stabilization window, something is blocking scale-up (e.g. insufficient node capacity — check `kubectl describe node` for `Insufficient cpu` events).

## Mitigation

1. Install/fix metrics-server as above if that's the root cause.
2. Confirm `k8s/deployment.yaml` still has `resources.requests.cpu` set (HPA requires this to calculate utilisation).
3. If at `maxReplicas`, this is expected behaviour, not a bug — see runbook 04 for the capacity conversation.
4. If blocked by node capacity, add nodes (cloud) or increase resources on the local cluster (`kind`/`minikube` config).

## Recovery verification

```bash
kubectl -n kubepulse get hpa kubepulse -w
```
Confirm `TARGETS` shows a numeric percentage (not `<unknown>`) and replica count moves toward `desired` within the stabilization window.

## Escalation considerations

- Node-capacity constraints blocking scale-up require infra capacity planning — escalate to the platform/infra team.

## Post-incident checks

- Re-run Experiment 3 in `docs/experiments.md` end-to-end to confirm HPA scale-up and scale-down both work.
