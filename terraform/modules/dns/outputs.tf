output "lb_ip" { value = google_compute_global_address.lb.address }
output "name_servers" { value = google_dns_managed_zone.this.name_servers }
