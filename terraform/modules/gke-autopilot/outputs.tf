output "name" { value = google_container_cluster.this.name }
output "endpoint" { value = google_container_cluster.this.endpoint }
output "workload_pool" { value = "${var.project_id}.svc.id.goog" }
