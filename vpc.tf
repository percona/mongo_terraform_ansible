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
  name = "${var.env_tag}-${var.subnet_name}"
  ip_cidr_range = var.subnet
  region = var.region
  network = google_compute_network.vpc-network.id
}
