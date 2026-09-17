# Validation Report

This report documents what was actually executed against the real toolchain
on a normal Windows 11 developer machine with Docker Desktop, with evidence,
versus what remains untested. It supersedes an earlier version of this
document written against a different, network-restricted sandbox
environment (one where container registries were unreachable and Kubernetes
pod scheduling was blocked by a host-specific containerd/CRI limitation).
That environment no longer applies here: this report reflects a real
Docker Desktop + `kind` environment with normal internet access, where
Docker, Kubernetes, HPA, Prometheus, and Grafana were all exercised for
real, end to end.

## Environment (actually used)

| Tool | Version |
|---|---|
| OS | Windows 11 Home Single Language (build 10.0.22621) |
| Docker | Docker Desktop 29.8.0, Linux containers via WSL2 |
| Kubernetes | `kind` v0.-series, node image `kindest/node:v1.37.0` |
| kubectl | v1.36.1 |
| Terraform | v1.16.2 |
| Python | 3.10.6 (project venv) |

No network egress restrictions applied in this environment — Docker Hub,
GitHub, PyPI, and HashiCorp's provider registry were all reachable normally.

## Test summary

| Area | Status |
|---|---|
| Application (unit + integration tests) | **PASS** — 22/22 |
| Lint / format (ruff, black) | **PASS** |
| Docker build (real `Dockerfile`) | **PASS** — pulled `python:3.12-slim` from Docker Hub normally |
| Docker run / endpoints / healthcheck / non-root | **PASS** |
| Kubernetes cluster (`kind`) | **PASS** — node reached `Ready` |
| KubePulse deployed to the cluster | **PASS** — `kubectl apply -k k8s/`, rollout succeeded, pods scheduled and `Ready` |
| Metrics Server | **PASS** — installed, `kubectl top nodes`/`top pods` both work |
| HPA (real scaling) | **PASS** — real scale-up 2→4 and scale-down 4→3→2 observed under real CPU load (see caveats below) |
| Load testing (in-cluster, via the Service) | **PASS** — 771 requests, 0 failures |
| Failure injection (pod delete/recreate) | **PASS** — 6s recovery, no observed Service downtime |
| Prometheus (docker-compose stack) | **PASS** — healthy, scraping the app, KubePulse metrics queryable, alert rules loaded |
| Grafana (docker-compose stack) | **PASS** — healthy, datasource and dashboard provisioned correctly |
| Terraform (`fmt -check`, `validate`) | **PASS** |
| Prometheus/Grafana *inside* the Kubernetes cluster | **NOT DEPLOYED** — by this project's own design (see §6) |
| Kubernetes-level Prometheus alerts (restart/CPU/replica-availability) | **NOT VALIDATED** — require `kube-state-metrics`/cAdvisor, not present in either environment tested |

## 1. Application — PASS

```
22 passed in ~5s
```
17 unit tests, 5 integration tests against a real `uvicorn` subprocess.
`ruff check .` and `black --check .` both clean.

## 2. Docker — PASS

`docker build -t kubepulse:local -f Dockerfile .` succeeded using the real,
unmodified production `Dockerfile` — `python:3.12-slim` was pulled from
Docker Hub normally, no network workaround needed. Final image: **243MB**.

The built image was run as a real container (`docker run -d -p
18000:8000 kubepulse:local`) and exercised endpoint-by-endpoint:

| Endpoint | Result |
|---|---|
| `GET /health` | `200` |
| `GET /ready` | `200` |
| `GET /api/v1/status` | `200 {"healthy":true,"ready":true,...}` |
| `GET /api/v1/work?iterations=2000` | `200 {"iterations":2000,"duration_seconds":0.0011}` |
| `GET /api/v1/error?rate=1.0` (×5) | `500` ×5 |
| `GET /api/v1/error?rate=0.0` (×5) | `200` ×5 |
| `GET /metrics` | Prometheus text format, counters matched the requests made |

Docker's own `HEALTHCHECK` reported `healthy` (`docker inspect` →
`{"Status":"healthy","FailingStreak":0}`). `docker exec ... whoami`/`id`
confirmed the process runs as the non-root `kubepulse` user (uid 999, gid
999), matching the Dockerfile's `USER kubepulse` step. The container was
cleaned up with `docker rm -f`; graceful SIGTERM shutdown timing was not
separately measured in this pass.

## 3. Kubernetes cluster and deployment — PASS

A local `kind` cluster (`kubepulse-validate`) was created, the built image
loaded into it directly (`kind load docker-image`), and the real manifests
applied unmodified:

```
kubectl apply -k k8s/
kubectl -n kubepulse rollout status deployment/kubepulse --timeout=120s
# → deployment "kubepulse" successfully rolled out
```

2/2 pods reached `Running`/`Ready` with zero restarts on initial rollout.
`kubectl exec ... id` confirmed `uid=1000`, matching the Deployment's
`securityContext.runAsUser: 1000` — the pod's non-root and
`readOnlyRootFilesystem: true` constraints did not break the application.
The Service was exercised via `kubectl port-forward`, reproducing the same
endpoint results as the Docker-only test above, including `/api/v1/error`
returning 500 at `rate=1.0` and 200 at `rate=0.0` through the full
Kubernetes networking path. The PodDisruptionBudget's computed status
(`currentHealthy: 2, disruptionsAllowed: 1`) matched live pod state.

## 4. Metrics Server and HPA — PASS, with caveats

The official `metrics-server` manifest was applied and patched with
`--kubelet-insecure-tls` (required on `kind`, whose kubelet certs aren't
CA-valid — this patch is scripted in `scripts/create-cluster.sh`).
`kubectl top nodes` and `kubectl top pods -n kubepulse` both returned real
data within ~30 seconds of metrics-server becoming `Ready`.

Sustained CPU load was generated against `/api/v1/work` through a
port-forward tunnel. **Real scale-up was observed**: CPU utilization peaked
at 152% of the HPA's 70% target, and the Deployment scaled from 2 to 4
replicas within about a minute, consistent with the configured
`scaleUp: {type: Percent, value: 100, periodSeconds: 30}` policy. **Real
scale-down was subsequently observed**: once load subsided, replicas
returned from 4 → 3 → 2 over the following ~2–3 minutes, consistent with
the `scaleDown` stabilization window.

**Caveat**: `kubectl port-forward` to a Service pins its tunnel to a single
backend pod rather than load-balancing like real Service traffic, so the
load was not evenly distributed and did not run at full intensity for the
whole intended window — see §7 and `docs/experiments.md` (Experiment 3b)
for the full, transparent account, including a liveness-probe restart this
uncovered under that concentrated load pattern. HPA never reached
`maxReplicas: 8` in this run, and memory was never the binding metric.

## 5. Load testing — PASS

The project's own `load-testing/locustfile.py` was run headless (20 users,
60s) against the live Kubernetes Service (through port-forward):
**771 requests, 0 failures (0.00%)**, including intentional
`/api/v1/error` 500s (correctly treated as expected by the locustfile).
Latency was higher than the bare-process baseline in
`docs/experiments.md` (median 690ms vs. 3ms) — expected, given the pods are
capped at 300m CPU and traffic traverses a port-forward tunnel, not a
defect. The original bare-`uvicorn` baseline in `docs/experiments.md`
(423 requests, 0% failures) remains valid, independent evidence and is not
superseded by this run — it exercises a different deployment shape (no
container, no CPU limit).

## 6. Failure injection and recovery — PASS

A running pod was deleted directly (`kubectl delete pod ...`) while another
process held an active connection to the Service. The Deployment controller
created a replacement pod that reached `Ready` in **6 seconds**. The
Service (`/health`, `/api/v1/status`) responded correctly immediately
before and after the deletion — no observed downtime through the Service
endpoint.

## 7. Liveness probe under extreme CPU saturation — discovered, documented, not yet fixed

Driving `/api/v1/work` with 20 concurrent callers at 5,000,000 iterations
each — far beyond this project's own normal/documented load profile —
caused a pod's `/health` liveness probe to fail and the container to be
restarted by kubelet, because `/health` shares FastAPI's request thread
pool and the same CPU cgroup budget as the CPU-bound work handler. The
project's own mixed-traffic Locust run (§5) produced **zero** restarts.
Full analysis, including why readiness and liveness serve different
purposes here and what a production-appropriate fix would look like, is in
`docs/experiments.md` under "Experiment 3b — Liveness probe interaction
under extreme CPU saturation." This is intentionally left unfixed for now
per an explicit decision to document rather than silently patch it.

## 8. Prometheus and Grafana (docker-compose stack) — PASS

`docker compose config` rendered without errors. `docker compose up --build
-d` brought up `kubepulse-app`, `kubepulse-prometheus`, and
`kubepulse-grafana`; the app reported `(healthy)` within ~9 seconds.

- **Prometheus**: `/-/healthy` → "Healthy", `/-/ready` → "Ready", config
  loaded without error. Both configured scrape targets (`kubepulse-app`,
  `prometheus` self-scrape) reported `up`. After generating a few requests
  against the app, `kubepulse_http_requests_total` and
  `kubepulse_http_errors_total` were both queryable via Prometheus's own
  `/api/v1/query` with real, matching values. All 6 alert rules across both
  rule groups loaded successfully via `/api/v1/rules`.
- **Grafana**: `/api/health` → `{"database":"ok"}`. The provisioned
  Prometheus datasource (`url: http://prometheus:9090`, `isDefault: true`)
  and the "KubePulse Overview" dashboard (11 panels, confirmed via the
  Grafana API) both loaded correctly. A handful of `error`-level lines
  appear in Grafana's own startup log, but they are Grafana-internal noise
  (a duplicate built-in plugin registration) and expected messages about
  optional `plugins/`/`alerting/` provisioning directories this project
  doesn't use — not a KubePulse configuration defect.

The stack was torn down cleanly afterward (`docker compose down`).

**Note on scope**: Prometheus and Grafana are provisioned only via
`docker-compose.yml` in this project — `k8s/` intentionally contains no
Prometheus/Grafana Deployment of its own, only `prometheus.io/scrape`
annotations for an external Prometheus to discover. The
`kubepulse-kubernetes` alert group (pod-restart, CPU-saturation, and
replica-availability alerts) depends on `kube-state-metrics`/cAdvisor
metrics, which are present in neither this project's `docker-compose` stack
nor the `kind` cluster used above — those three alert rules are
**syntactically valid and loaded, but not runtime-validated** against real
firing conditions.

## 9. Terraform — PASS

`terraform fmt -check` initially failed on two files
(`terraform/namespace.tf`, `terraform/workload.tf` — cosmetic alignment
only); both were fixed with `terraform fmt` and now pass. `terraform init
-backend=false -input=false` installed the `hashicorp/kubernetes` provider
(v2.38.0) normally from the public registry, and `terraform validate`
reports **"Success! The configuration is valid."** `terraform plan`/`apply`
were not run, and no cloud provider is configured — `main.tf` only declares
the local `kubernetes` provider against `var.kubeconfig_path`. The optional
`terraform/cloud/` variant (EKS/GKE/AKS) was not exercised at all; it
requires separate cloud credentials and is disabled by default.

## Known, currently-unresolved issues

- `DeprecationWarning: The anyio.abc.BlockingPortal alias is deprecated` —
  originates from `starlette/testclient.py`, a third-party dependency;
  `fastapi==0.115.0` pins `starlette<0.39.0`, and no compatible `starlette`
  release in that range fixes it. Not resolved without a larger `fastapi`
  version bump, which was judged out of scope.
- The `kubepulse-kubernetes` Prometheus alert group is unvalidated at
  runtime (§8).
- The liveness/CPU-saturation interaction (§7) remains unfixed by design
  decision, not oversight — see `docs/experiments.md` for the full
  reasoning and options considered.

## Conclusion

Unlike the environment this report previously described, this validation
ran against a real Docker Desktop and `kind` Kubernetes setup with normal
network access, and exercised the full stack for real: Docker build and
run, a real Kubernetes control plane and scheduler, real HPA scale-up and
scale-down under real CPU load, real pod-failure injection and recovery,
and both Prometheus and Grafana running live and correctly wired to the
application's own metrics. The remaining gaps — Kubernetes-level alert
validation and the liveness/CPU-saturation trade-off — are genuine,
narrowly-scoped, and documented rather than hidden or assumed away.
