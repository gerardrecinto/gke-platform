variable "project_id" { type = string }
variable "location" { type = string }
variable "cluster_name" { type = string }
variable "cluster_id" { type = string }
variable "namespaces" {
  type    = list(string)
  default = ["orders"]
}
variable "retain_days" {
  type    = number
  default = 14
}
