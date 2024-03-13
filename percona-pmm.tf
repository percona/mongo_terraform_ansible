resource "google_compute_disk" "pmm_disk" {
  name  = "${var.env_tag}-percona-pmm-data"
  type  = var.data_disk_type
  size  = var.pmm_volume_size
  zone  = data.google_compute_zones.available.names[0]
}

resource "google_compute_instance" "pmm" {
  name = "${var.env_tag}-percona-pmm"
  machine_type = var.pmm_type
  zone  = data.google_compute_zones.available.names[0]
  tags = ["percona-pmm"]
  boot_disk {
    initialize_params {
    image = lookup(var.centos_amis, var.region)
    }
  }   
  attached_disk {
    source = google_compute_disk.pmm_disk.name
  }     
  network_interface {
    network = google_compute_network.vpc-network.id
    subnetwork = google_compute_subnetwork.vpc-subnet.id
    access_config {}
  }
  metadata = {
    ssh-keys = "${var.gce_ssh_user}:${file(var.gce_ssh_pub_key_file)}"
  }
  metadata_startup_script = <<EOT
    #! /bin/bash
    echo "Created"
EOT
}
resource "google_compute_firewall" "percona-pmm-firewall" {
  name = "${var.env_tag}-percona-pmm-firewall"
  network = google_compute_network.vpc-network.name
  direction = "INGRESS"
  source_ranges = ["0.0.0.0/0"]
  target_tags = ["${var.env_tag}-percona-pmm"]
  allow {
    protocol = "tcp"
    ports = ["22", "443"]
 }
}
