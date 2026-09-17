resource "kubernetes_namespace" "kubepulse" {
  metadata {
    name = var.namespace
    labels = {
      app = "kubepulse"
    }
  }
}

resource "kubernetes_config_map" "kubepulse" {
  metadata {
    name      = "kubepulse-config"
    namespace = kubernetes_namespace.kubepulse.metadata[0].name
    labels = {
      app = "kubepulse"
    }
  }

  data = {
    APP_NAME                = "kubepulse"
    APP_VERSION             = "1.0.0"
    LOG_LEVEL               = "INFO"
    PORT                    = "8000"
    SLOW_MIN_SECONDS        = "0.5"
    SLOW_MAX_SECONDS        = "2.0"
    ERROR_RATE              = "0.0"
    WORK_DEFAULT_ITERATIONS = "2000000"
    STARTUP_DELAY_SECONDS   = "0"
    FORCE_UNREADY           = "false"
    FORCE_UNHEALTHY         = "false"
  }
}
