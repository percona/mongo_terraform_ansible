# Gets the list of availability zones in selected gcp region
data "google_compute_zones" "available" {
	status = "UP"
}

# Set your desired network
resource "google_compute_network" "vpc-network" {
  name = "${var.env_tag}-${var.network_name}"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "vpc-subnet" {
  name = "${var.env_tag}-mongodb-terraform-subnet"
  ip_cidr_range = "10.30.0.0/16"
  region = var.region
  network = google_compute_network.vpc-network.id
}
