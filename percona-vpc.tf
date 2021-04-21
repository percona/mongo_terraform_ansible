# Gets the list of availability zones in selected gcp region
data "google_compute_zones" "available" {
	status = "UP"
}

resource "google_compute_network" "vpc-network" {
  name = "cio-emr-dw-lab-9974ed-terraform-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "vpc-subnet" {
  name = "mongodb-terraform-subnet"
  ip_cidr_range = "10.30.0.0/16"
  region = var.region
  network = google_compute_network.vpc-network.id
}