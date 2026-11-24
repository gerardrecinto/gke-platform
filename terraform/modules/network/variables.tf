variable "project_id" { type = string }
variable "region" { type = string }
variable "name" {
  type    = string
  default = "gke"
}
variable "node_cidr" {
  type    = string
  default = "10.10.0.0/20"
}
variable "pod_cidr" {
  type        = string
  default     = "10.20.0.0/16"
  description = "Secondary range for pods. A /16 holds 65,536 pod IPs; with 110 pods per node it fits about 590 nodes at /24 per node."
}
variable "service_cidr" {
  type    = string
  default = "10.30.0.0/20"
}
variable "node_tag" {
  type    = string
  default = "gke-node"
}
