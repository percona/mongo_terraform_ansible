resource "google_compute_instance" "mongos" {
  name = "${var.env_tag}-${var.mongos_tag}0${count.index}"
  machine_type = var.mongos_type
  zone  = data.google_compute_zones.available.names[count.index % length(data.google_compute_zones.available.names)]
  count = var.mongos_count
  tags = ["${var.env_tag}-${var.mongos_tag}"]
  labels = { 
    ansible-group = "mongos",
    environment = var.env_tag
  }
  boot_disk {
    initialize_params {
    image = lookup(var.image, var.region)
    }
  }   
  network_interface {
    network = google_compute_network.vpc-network.id
    subnetwork = google_compute_subnetwork.vpc-subnet.id
    access_config {}
  }
  metadata = {
    ssh-keys = join("\n", [for user, key_path in var.gce_ssh_users : "${user}:${file(key_path)}"])
  }
  scheduling {
    preemptible = var.use_spot_instances
    automatic_restart = var.use_spot_instances ? false : true
    provisioning_model = var.use_spot_instances ? "SPOT" : "STANDARD"
  }
  metadata_startup_script = <<EOT
    #! /bin/bash
    echo "Created"
EOT
}

resource "google_compute_firewall" "mongodb-mongos-firewall" {
  name = "${var.env_tag}-${var.mongos_tag}-firewall"
  network = google_compute_network.vpc-network.name
  direction = "INGRESS"
  source_ranges = ["0.0.0.0/0"]
  target_tags = ["${var.env_tag}-${var.mongos_tag}"]
  allow {
    protocol = "tcp"
    ports = "${var.mongos_ports}"
  }
}
