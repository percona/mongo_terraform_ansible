terraform {
  required_version = ">= 1.0" 
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

# Gets the list of availability zones in selected gcp region
data "google_compute_zones" "available" {
  status = "UP"
}