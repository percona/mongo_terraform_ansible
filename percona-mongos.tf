resource "google_compute_instance" "mongos" {
  name = "${var.env_tag}-mongo-router0${count.index}"
  machine_type = var.mongos_type
  zone  = data.google_compute_zones.available.names[count.index % 3]
  count = var.mongos_count
  tags = ["${var.env_tag}-mongodb-mongos"]
  labels = { 
    ansible-group = "mongos",
    environment = var.env_tag
  }
  boot_disk {
    initialize_params {
    image = lookup(var.centos_amis, var.region)
    }
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

resource "google_compute_firewall" "mongodb-mongos-firewall" {
  name = "${var.env_tag}-mongodb-mongos-firewall"
  network = google_compute_network.vpc-network.name
  direction = "INGRESS"
  source_ranges = ["0.0.0.0/0"]
  target_tags = ["${var.env_tag}-mongodb-mongos"]
  allow {
    protocol = "tcp"
    ports = "${var.mongos_ports}"
  }
}