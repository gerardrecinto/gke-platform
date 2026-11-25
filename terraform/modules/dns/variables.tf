variable "project_id" { type = string }
variable "dns_name" {
  type        = string
  description = "Zone name without the trailing dot, for example example.com."
}
