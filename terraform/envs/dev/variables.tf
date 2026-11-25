variable "project_id" { type = string }
variable "region" {
  type    = string
  default = "us-west1"
}
variable "authorized_networks" {
  type        = map(string)
  default     = {}
  description = "CIDRs allowed to reach the control plane, for example { office = \"203.0.113.0/24\" }."
}
variable "dns_name" {
  type    = string
  default = "example.com"
}
