.PHONY: install test lint format docker-build docker-run k8s-deploy k8s-delete load-test failure-inject validate clean run cluster-up cluster-down

VENV_PY := python3
IMAGE := kubepulse:local
NAMESPACE := kubepulse

install: ## Install runtime + dev dependencies
	$(VENV_PY) -m pip install --break-system-packages -r requirements-dev.txt

run: ## Run the app locally with uvicorn (reload enabled)
	uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload

test: ## Run unit + integration tests
	pytest tests/unit tests/integration -v --cov=app --cov-report=term-missing

lint: ## Run ruff static analysis
	ruff check app tests

format: ## Auto-format code with black
	black app tests

format-check: ## Check formatting without changing files
	black --check app tests

docker-build: ## Build the production Docker image
	docker build -t $(IMAGE) .

docker-run: ## Run the app in Docker on port 8000
	docker run --rm -p 8000:8000 --name kubepulse $(IMAGE)

compose-up: ## Start app + Prometheus + Grafana via docker-compose
	docker compose up --build -d

compose-down: ## Tear down the docker-compose stack
	docker compose down -v

cluster-up: ## Create a local kind cluster (+ metrics-server) for KubePulse
	bash scripts/create-cluster.sh

cluster-down: ## Delete the local kind cluster
	bash scripts/delete-cluster.sh

k8s-deploy: ## Apply all Kubernetes manifests
	kubectl apply -k k8s/

k8s-delete: ## Delete all KubePulse Kubernetes resources
	kubectl delete -k k8s/ --ignore-not-found

load-test: ## Run a headless Locust load test against localhost:8000
	bash scripts/load-test.sh

failure-inject: ## Run the failure injection experiment suite
	bash scripts/failure-injection.sh

validate: ## Run full static + runtime validation suite
	bash scripts/validate.sh

clean: ## Remove caches and generated artifacts
	find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	rm -rf .pytest_cache .ruff_cache htmlcov .coverage load-testing/results
