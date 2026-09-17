output "namespace" {
  description = "Namespace KubePulse was deployed into."
  value       = kubernetes_namespace.kubepulse.metadata[0].name
}

output "service_name" {
  description = "In-cluster Service name for KubePulse."
  value       = kubernetes_service.kubepulse.metadata[0].name
}

output "deployment_name" {
  description = "Deployment name for KubePulse."
  value       = kubernetes_deployment.kubepulse.metadata[0].name
}

output "hpa_name" {
  description = "HorizontalPodAutoscaler name for KubePulse."
  value       = kubernetes_horizontal_pod_autoscaler_v2.kubepulse.metadata[0].name
}
