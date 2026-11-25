resource "google_dns_managed_zone" "this" {
  name        = replace(var.dns_name, ".", "-")
  project     = var.project_id
  dns_name    = "${var.dns_name}."
  description = "Zone for ${var.dns_name}"

  dnssec_config {
    state = "on"
  }
}

# Points the host at the global static IP the Ingress or Gateway uses.
resource "google_dns_record_set" "app" {
  project      = var.project_id
  managed_zone = google_dns_managed_zone.this.name
  name         = "orders.${var.dns_name}."
  type         = "A"
  ttl          = 300
  rrdatas      = [google_compute_global_address.lb.address]
}

resource "google_compute_global_address" "lb" {
  project = var.project_id
  name    = "orders-api-ip"
}
