output "network" { value = google_compute_network.vpc.id }
output "subnetwork" { value = google_compute_subnetwork.nodes.id }
output "pods_range_name" { value = "pods" }
output "services_range_name" { value = "services" }
