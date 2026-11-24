output "google_sa_email" {
  value       = google_service_account.workload.email
  description = "Put this in the iam.gke.io/gcp-service-account annotation on the Kubernetes service account."
}
