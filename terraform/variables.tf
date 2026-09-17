variable "kubeconfig_path" {
  description = "Path to the kubeconfig file for the target (local) cluster."
  type        = string
  default     = "~/.kube/config"
}

variable "kube_context" {
  description = "kubeconfig context to use (e.g. kind-kubepulse)."
  type        = string
  default     = "kind-kubepulse"
}

variable "namespace" {
  description = "Kubernetes namespace KubePulse is deployed into."
  type        = string
  default     = "kubepulse"
}

variable "app_image" {
  description = "Container image (repo:tag) for the KubePulse application."
  type        = string
  default     = "kubepulse:local"
}

variable "replicas" {
  description = "Baseline replica count for the KubePulse Deployment."
  type        = number
  default     = 2
}

variable "min_replicas" {
  description = "HPA minimum replica count."
  type        = number
  default     = 2
}

variable "max_replicas" {
  description = "HPA maximum replica count."
  type        = number
  default     = 8
}

variable "cpu_target_percent" {
  description = "HPA target average CPU utilisation percentage."
  type        = number
  default     = 70
}
