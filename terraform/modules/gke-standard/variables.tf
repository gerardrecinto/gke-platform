variable "project_id" { type = string }
variable "name" { type = string }
variable "location" {
  type        = string
  description = "Region for a regional cluster (three zones) or a zone for a zonal one."
}
variable "network" { type = string }
variable "subnetwork" { type = string }
variable "pods_range_name" { type = string }
variable "services_range_name" { type = string }
variable "master_cidr" {
  type    = string
  default = "172.16.0.0/28"
}
variable "authorized_networks" {
  type        = map(string)
  default     = {}
  description = "Name to CIDR map allowed to reach the control plane endpoint. Empty means only the cluster's own VPC and Google-owned ranges."
}
variable "release_channel" {
  type    = string
  default = "REGULAR"
}
variable "machine_type" {
  type    = string
  default = "e2-standard-4"
}
variable "min_nodes_per_zone" {
  type    = number
  default = 1
}
variable "max_nodes_per_zone" {
  type    = number
  default = 4
}
variable "node_tag" {
  type    = string
  default = "gke-node"
}
variable "deletion_protection" {
  type    = bool
  default = true
}
variable "labels" {
  type    = map(string)
  default = {}
}
