# Local-development Terraform configuration for KubePulse.
#
# This manages Kubernetes-side resources (namespace, config, workloads) on a
# local cluster (kind/minikube/k3d) via the Kubernetes provider, driven by
# the manifests under ../k8s. It assumes `kubectl` is already pointed at a
# running local cluster (see docs/architecture.md for how to create one with
# kind) — Terraform does not create the cluster itself, keeping this stack
# free of any cloud dependency or cost.
#
# For an OPTIONAL cloud deployment (e.g. EKS/GKE/AKS), see
# terraform/cloud/ — disabled by default and requires its own credentials.
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.31"
    }
  }
}

provider "kubernetes" {
  config_path    = var.kubeconfig_path
  config_context = var.kube_context
}
