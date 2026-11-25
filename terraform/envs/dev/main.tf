locals {
  labels = { env = "dev", managed-by = "terraform", repo = "gke-platform" }
}

module "network" {
  source     = "../../modules/network"
  project_id = var.project_id
  region     = var.region
  name       = "gke-dev"
}

# Standard: you choose machine types and bounds. Use it for DaemonSets, privileged agents, GPUs and tuned bin packing.
module "standard" {
  source              = "../../modules/gke-standard"
  project_id          = var.project_id
  name                = "std-dev"
  location            = var.region
  network             = module.network.network
  subnetwork          = module.network.subnetwork
  pods_range_name     = module.network.pods_range_name
  services_range_name = module.network.services_range_name
  authorized_networks = var.authorized_networks
  deletion_protection = false
  labels              = local.labels
}

# Autopilot: Google runs the nodes. Use it for ordinary stateless and stateful services where you want requests to be the only knob.
module "autopilot" {
  source              = "../../modules/gke-autopilot"
  project_id          = var.project_id
  name                = "ap-dev"
  location            = var.region
  network             = module.network.network
  subnetwork          = module.network.subnetwork
  pods_range_name     = module.network.pods_range_name
  services_range_name = module.network.services_range_name
  authorized_networks = var.authorized_networks
  deletion_protection = false
  labels              = local.labels
}

module "orders_workload_identity" {
  source         = "../../modules/workload-identity"
  project_id     = var.project_id
  google_sa_name = "orders-api"
  k8s_namespace  = "orders"
  k8s_sa_name    = "orders-api"
  roles          = ["roles/pubsub.publisher"]
}

module "observability" {
  source       = "../../modules/observability"
  project_id   = var.project_id
  cluster_name = module.standard.name
}

# Backup for GKE needs the add-on enabled on the cluster; see docs/RUNBOOK.md.
module "backup" {
  source       = "../../modules/backup"
  project_id   = var.project_id
  location     = var.region
  cluster_name = module.standard.name
  cluster_id   = module.standard.id
}

# Reserves the global IP named in k8s/ingress and points orders.<domain> at it.
module "dns" {
  source     = "../../modules/dns"
  project_id = var.project_id
  dns_name   = var.dns_name
}
