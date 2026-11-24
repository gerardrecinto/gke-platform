# Autopilot: Google manages nodes, so there is no node pool, no machine type and no Cluster Autoscaler to tune.
# You are billed for pod resource requests, so requests are the cost control.
resource "google_container_cluster" "this" {
  name     = var.name
  project  = var.project_id
  location = var.location

  enable_autopilot    = true
  network             = var.network
  subnetwork          = var.subnetwork
  deletion_protection = var.deletion_protection

  release_channel {
    channel = var.release_channel
  }

  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_range_name
    services_secondary_range_name = var.services_range_name
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = var.master_cidr
  }

  master_authorized_networks_config {
    dynamic "cidr_blocks" {
      for_each = var.authorized_networks
      content {
        cidr_block   = cidr_blocks.value
        display_name = cidr_blocks.key
      }
    }
  }

  # Workload Identity is always on in Autopilot; the pool is declared so the output is explicit.
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  resource_labels = var.labels
}
