variable "project_id" { type = string }
variable "google_sa_name" { type = string }
variable "k8s_namespace" { type = string }
variable "k8s_sa_name" { type = string }
variable "roles" {
  type        = list(string)
  default     = []
  description = "Project roles for the workload. Prefer resource-level bindings where the service supports them."
}
