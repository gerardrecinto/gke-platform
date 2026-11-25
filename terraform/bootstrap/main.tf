# Run once, with local state, to create the bucket that holds state for terraform/envs/*.
# Then uncomment the gcs backend block in envs/dev/versions.tf and run `terraform init -migrate-state`.
terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

variable "project_id" { type = string }
variable "region" {
  type    = string
  default = "us-west1"
}

provider "google" {
  project = var.project_id
  region  = var.region
}

resource "google_storage_bucket" "tfstate" {
  name                        = "${var.project_id}-tfstate"
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false

  # Every apply writes a new state version; keep the last 20 so a bad apply can be rolled back.
  versioning {
    enabled = true
  }
  lifecycle_rule {
    condition {
      num_newer_versions = 20
      with_state         = "ARCHIVED"
    }
    action {
      type = "Delete"
    }
  }
}

output "state_bucket" { value = google_storage_bucket.tfstate.name }
