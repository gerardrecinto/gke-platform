variable "project_id" { type = string }
variable "name" { type = string }
variable "location" { type = string }
variable "network" { type = string }
variable "subnetwork" { type = string }
variable "pods_range_name" { type = string }
variable "services_range_name" { type = string }
variable "master_cidr" {
  type    = string
  default = "172.16.0.16/28"
}
variable "authorized_networks" {
  type    = map(string)
  default = {}
}
variable "release_channel" {
  type    = string
  default = "REGULAR"
}
variable "deletion_protection" {
  type    = bool
  default = true
}
variable "labels" {
  type    = map(string)
  default = {}
}
