# KubePulse — Kubernetes SRE & Reliability Platform

A small, production-style Python service deployed to Kubernetes to
demonstrate practical SRE and reliability engineering: health probes,
resource limits, rolling deployments, autoscaling, Prometheus/Grafana
observability, alerting, incident runbooks, and reproducible failure
injection / load testing experiments.

## Project overview

KubePulse is a FastAPI service with endpoints that produce realistic,
controllable application behaviour — successful requests, configurable
latency, controlled errors, and CPU-bound work — instrumented with
Prometheus metrics. It's deployed to Kubernetes with liveness/readiness/
startup probes, resource requests/limits, a rolling-update strategy, and a
HorizontalPodAutoscaler. Around it sits a Prometheus + Grafana stack, a
Locust load-testing setup, failure-injection scripts, and documented
incident runbooks — everything needed to *observe*, *break*, and *recover*
the service, not just deploy it.

## Architecture

See [`docs/architecture.md`](docs/architecture.md) for the full diagram and
component rationale. In short:

```
User → Load Generator (Locust) → Kubernetes Service → Pods (FastAPI)
                                                          │
                                                          ▼
                                        Prometheus ← kube-state-metrics / cAdvisor
                                             │
                                             ▼
                                          Grafana
     HorizontalPodAutoscaler ⇄ Pods, driven by metrics-server
```

## Features

- FastAPI service with `/`, `/health`, `/ready`, `/metrics`, `/api/v1/status`, `/api/v1/work`, `/api/v1/slow`, `/api/v1/error`
- Prometheus instrumentation: request count, error count, latency histogram (P50/P95/P99), CPU-work duration, health/ready gauges
- Kubernetes manifests: Namespace, Deployment (rolling updates, probes, resource limits), Service, ConfigMap, Secret example, ServiceAccount + RBAC, HPA, PodDisruptionBudget
- Terraform (Kubernetes provider) equivalent of the manifests, for a local cluster — no cloud cost required
- Docker: non-root, healthchecked production image + docker-compose stack (app + Prometheus + Grafana) for local development
- GitHub Actions CI (lint, format, unit + integration tests, Docker build, manifest/YAML validation) and CD (build/push to GHCR, optional deploy)
- Grafana dashboard (auto-provisioned) covering all four golden signals
- Prometheus alert rules with documented thresholds (`docs/observability.md`)
- Six incident runbooks (`docs/runbooks/`)
- Locust load test + failure-injection scripts (pod failure, application errors, CPU saturation/HPA)
- 22 automated tests (unit + real-process integration tests), all passing

## Technology stack

| Tool | Why |
|---|---|
| Python / FastAPI | Typed, async, minimal-boilerplate API framework with built-in OpenAPI docs |
| prometheus-client | Standard, dependency-light Prometheus instrumentation for Python |
| Docker | Reproducible, portable packaging |
| Kubernetes | The reliability substrate being demonstrated (probes, HPA, rolling updates) |
| Terraform | Declarative, reproducible infra-as-code against the Kubernetes provider |
| Prometheus + Grafana | De facto standard Kubernetes observability stack |
| Locust | Python-native load generation, easy to script realistic mixed traffic |
| GitHub Actions | Standard, free CI/CD for a public repository |
| pytest | Standard Python testing, supports both mocked unit tests and real-process integration tests |

## Repository structure

```
kube-pulse/
├── app/                  FastAPI application (routes, config, metrics, services)
├── tests/                unit/ and integration/ pytest suites
├── k8s/                  Kubernetes manifests (+ kustomization.yaml)
├── terraform/             Local-cluster Terraform (+ terraform/cloud/ optional stub)
├── monitoring/            Prometheus config/alerts + Grafana provisioning/dashboards
├── load-testing/          Locust locustfile + results/
├── scripts/               setup/validate/deploy/test/load-test/failure-injection/cleanup
├── docs/                  architecture, observability, experiments, runbooks/
├── .github/workflows/     ci.yml, cd.yml
├── Dockerfile, docker-compose.yml
└── Makefile
```

## Prerequisites

Always required:
- Python 3.12+
- `pip`

Optional, depending on what you want to run:
- Docker (image build, docker-compose stack)
- `kubectl` + a local cluster tool (`kind`, `minikube`, or `k3d`) for Kubernetes deployment
- `terraform` >= 1.5 (Kubernetes-provider deployment)
- `locust` (installed via `requirements-dev.txt`)

## Installation

```bash
git clone <your-fork-url>
cd kube-pulse
python3 -m pip install --break-system-packages -r requirements-dev.txt
# or: make install
```

## Running locally

```bash
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
# or: make run
curl http://localhost:8000/health
```

## Running with Docker / docker-compose

```bash
docker build -t kubepulse:local .
docker run --rm -p 8000:8000 kubepulse:local

# Full local observability stack (app + Prometheus + Grafana):
docker compose up --build -d
# App:        http://localhost:8000
# Prometheus: http://localhost:9090
# Grafana:    http://localhost:3000  (user: admin / pass: admin, or anonymous Viewer access)
docker compose down -v
```

## Deploying to Kubernetes

```bash
# 1. Create a local cluster (kind) + metrics-server (needed for HPA)
./scripts/create-cluster.sh
# or: make cluster-up

# 2. Build and load the image
docker build -t kube-pulse:local .
kind load docker-image kube-pulse:local --name kubepulse

# 3. Apply manifests
kubectl apply -k k8s/
kubectl -n kubepulse rollout status deployment/kubepulse

# 4. Access the service
kubectl -n kubepulse port-forward svc/kubepulse 8000:80

# Cleanup
./scripts/delete-cluster.sh
# or: make cluster-down
```

Or via the provided script: `./scripts/deploy.sh` (runs steps 2–3 for you against whatever cluster your current `kubectl` context points at).

### Deploying with Terraform (alternative to step 3 above)

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

## Accessing Grafana

**Via docker-compose**: open `http://localhost:3000` (admin/admin, or anonymous Viewer access is enabled). The "KubePulse Overview" dashboard is auto-provisioned from `monitoring/grafana/dashboards/kubepulse-overview.json`.

**Via Kubernetes**: install `kube-prometheus-stack` (or your own Prometheus/Grafana) and point it at `monitoring/prometheus/prometheus-k8s.yml` and `monitoring/grafana/dashboards/kubepulse-overview.json`; then:
```bash
kubectl -n <grafana-namespace> port-forward svc/grafana 3000:80
```

## Running tests

```bash
pytest tests/unit tests/integration -v --cov=app
# or: make test
```

## Running load tests

```bash
# Against a locally running app (uvicorn or docker-compose)
HOST=http://localhost:8000 ./scripts/load-test.sh
# or: make load-test
```
Results are written to `load-testing/results/*_stats.csv`.

## Failure injection

```bash
# Requires a Kubernetes deployment of KubePulse
./scripts/failure-injection.sh
# or: make failure-inject
```
See `docs/experiments.md` for the full experiment write-up and
`docs/runbooks/` for how to respond to each failure mode.

## Cleanup

```bash
./scripts/cleanup.sh
# or: make clean   (local caches only)
kubectl delete -k k8s/            # remove Kubernetes resources
docker compose down -v            # remove docker-compose stack
kind delete cluster --name kubepulse
```

## Environment limitations in this build

This project was built and validated in a network-restricted sandbox.
Rather than stopping at "Docker/Kubernetes aren't available," the build
process installed Docker (`apt-get install docker.io`) and ran it, built and
ran the application container end-to-end (all 8 endpoints tested against a
real running container, healthcheck verified, graceful shutdown verified),
and stood up a real single-node Kubernetes control plane (k3s) that reached
`Ready`. Actual pod scheduling in that specific sandbox is blocked by a
deep, root-caused containerd/CRI incompatibility with the sandbox's nested
kernel/cgroup setup — **not** a defect in KubePulse's own configuration.

The full, honest breakdown — what was actually executed with evidence, what
was blocked and why (with the diagnostic steps taken to isolate the cause),
and exact commands to complete validation on a normal machine — is in
[`docs/validation-report.md`](docs/validation-report.md). See also
[`docs/experiments.md`](docs/experiments.md) for load-test and failure-
injection results, real where executed and clearly labelled
`NOT EXECUTED — ENVIRONMENT LIMITATION` where not.

## License

MIT — see [`LICENSE`](LICENSE).
