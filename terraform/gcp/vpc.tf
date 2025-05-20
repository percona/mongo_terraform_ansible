# Gets the list of availability zones in selected gcp region
data "google_compute_zones" "available" {
  status = "UP"
}

# Set your desired VPC
resource "google_compute_network" "vpc-network" {
  name = local.vpc
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "vpc-subnet" {
  name = "${var.subnet_name}"
  ip_cidr_range = var.subnet_cidr
  region = var.region
  network = google_compute_network.vpc-network.id
}

resource "google_compute_firewall" "internal" {
  name    = "allow-internal"
  network = google_compute_network.vpc-network.id

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = [ var.subnet_cidr ] 
  direction     = "INGRESS"
  priority      = 65534
}

resource "google_compute_firewall" "icmp" {
  name    = "allow-icmp"
  network = google_compute_network.vpc-network.id

  allow {
    protocol = "icmp"
  }

  source_ranges = [ "0.0.0.0/0" ] 
  direction     = "INGRESS"
  priority      = 65534
}

resource "google_compute_firewall" "ssh" {
  name    = "allow-ssh"
  network = google_compute_network.vpc-network.id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = [ var.source_ranges ]
  direction     = "INGRESS"
  priority      = 65534
}