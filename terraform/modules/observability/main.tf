# Alerts on Google Cloud Managed Service for Prometheus metrics. PromQL runs in Cloud Monitoring.
resource "google_monitoring_notification_channel" "email" {
  count        = var.alert_email == "" ? 0 : 1
  project      = var.project_id
  display_name = "gke-platform on-call"
  type         = "email"
  labels       = { email_address = var.alert_email }
}

locals {
  channels = google_monitoring_notification_channel.email[*].id
}

resource "google_monitoring_alert_policy" "hpa_at_max" {
  project      = var.project_id
  display_name = "HPA pinned at max replicas for 15 minutes"
  combiner     = "OR"
  conditions {
    display_name = "current replicas equal max replicas"
    condition_prometheus_query_language {
      query    = "kube_horizontalpodautoscaler_status_current_replicas{cluster=\"${var.cluster_name}\"} >= kube_horizontalpodautoscaler_spec_max_replicas{cluster=\"${var.cluster_name}\"}"
      duration = "900s"
    }
  }
  notification_channels = local.channels
  documentation {
    mime_type = "text/markdown"
    content   = "The HPA cannot add replicas. Raise maxReplicas, or check whether the node pool has hit its Cluster Autoscaler maximum. See docs/RUNBOOK.md."
  }
}

resource "google_monitoring_alert_policy" "crash_loop" {
  project      = var.project_id
  display_name = "Container restarting repeatedly"
  combiner     = "OR"
  conditions {
    display_name = "more than 3 restarts in 10 minutes"
    condition_prometheus_query_language {
      query    = "increase(kube_pod_container_status_restarts_total{cluster=\"${var.cluster_name}\"}[10m]) > 3"
      duration = "300s"
    }
  }
  notification_channels = local.channels
}

resource "google_monitoring_alert_policy" "pvc_filling" {
  project      = var.project_id
  display_name = "Persistent volume will fill within 24 hours"
  combiner     = "OR"
  conditions {
    display_name = "predict_linear says full in 24h"
    condition_prometheus_query_language {
      query    = "predict_linear(kubelet_volume_stats_available_bytes{cluster=\"${var.cluster_name}\"}[6h], 24 * 3600) < 0"
      duration = "600s"
    }
  }
  notification_channels = local.channels
}

# Count error-level container logs so a log spike can alert without a custom agent.
resource "google_logging_metric" "container_errors" {
  project = var.project_id
  name    = "gke_container_errors"
  filter  = "resource.type=\"k8s_container\" AND resource.labels.cluster_name=\"${var.cluster_name}\" AND severity>=ERROR"
  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
  }
}
