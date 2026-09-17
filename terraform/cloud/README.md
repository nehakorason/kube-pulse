# Optional Cloud Deployment (NOT required to run KubePulse)

Everything in the parent `terraform/` directory targets a **local**
Kubernetes cluster (kind/minikube/k3d) and requires no cloud account, no
credentials, and no cost.

This directory is a placeholder for an **optional** cloud deployment (e.g.
AWS EKS, GCP GKE, Azure AKS). It is intentionally left unimplemented because:

- It would require real cloud credentials and would incur real cost.
- The reliability/SRE concepts KubePulse demonstrates (probes, HPA, rolling
  updates, alerting, failure injection) are fully demonstrable on a free
  local cluster.

If you want to extend KubePulse to a real cloud provider, the recommended
approach is:

1. Add a `main.tf` here using the relevant provider (`hashicorp/aws`,
   `hashicorp/google`, or `hashicorp/azurerm`) to provision a managed
   Kubernetes cluster.
2. Reuse the existing Kubernetes-provider resources in `../*.tf` (namespace,
   deployment, service, HPA) by pointing `kubeconfig_path`/`kube_context` at
   the new cluster, or by adapting them into a shared Terraform module.
3. Keep this module behind an explicit `-target` or a separate
   `terraform init` so a plain `terraform apply` in the repository root
   never touches cloud resources by accident.

No cloud resources are created by this repository as-is.
