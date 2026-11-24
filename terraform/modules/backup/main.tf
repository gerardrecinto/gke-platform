# Backup for GKE: scheduled backups of persistent volumes and the Kubernetes resources that use them.
resource "google_gke_backup_backup_plan" "daily" {
  name     = "${var.cluster_name}-daily"
  project  = var.project_id
  location = var.location
  cluster  = var.cluster_id

  retention_policy {
    backup_delete_lock_days = 1
    backup_retain_days      = var.retain_days
  }

  backup_schedule {
    cron_schedule = "0 3 * * *"
  }

  backup_config {
    include_volume_data = true
    include_secrets     = false
    selected_namespaces {
      namespaces = var.namespaces
    }
  }
}
