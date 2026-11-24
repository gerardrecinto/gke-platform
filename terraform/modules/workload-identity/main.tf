# One Google service account per workload, bound to one Kubernetes service account.
# The pod never holds a key file. GKE exchanges the pod's token for a short-lived Google token.
resource "google_service_account" "workload" {
  project      = var.project_id
  account_id   = var.google_sa_name
  display_name = "Workload ${var.k8s_namespace}/${var.k8s_sa_name}"
}

resource "google_service_account_iam_member" "bind" {
  service_account_id = google_service_account.workload.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.k8s_namespace}/${var.k8s_sa_name}]"
}

resource "google_project_iam_member" "roles" {
  for_each = toset(var.roles)
  project  = var.project_id
  role     = each.value
  member   = "serviceAccount:${google_service_account.workload.email}"
}
