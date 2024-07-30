resource "google_compute_instance" "arbiter" {
  name = "${var.env_tag}-${var.shard_tag}0${floor(count.index / var.arbiters_per_replset )}arb${count.index % var.arbiters_per_replset}"
  machine_type = var.arbiter_type
  zone  = data.google_compute_zones.available.names[count.index % length(data.google_compute_zones.available.names)]
  count = var.shard_count * var.arbiters_per_replset
  tags = ["${var.env_tag}-${var.arbiter_tag}"]
  labels = { 
    ansible-group = floor(count.index / var.arbiters_per_replset ),
    ansible-index = count.index % var.arbiters_per_replset,
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
    automatic_restart = var.use_spot_instances ? true : false
    provisioning_model = var.use_spot_instances ? "SPOT" : "STANDARD"
  }
  metadata_startup_script = <<EOT
    #! /bin/bash
    echo "Created"
EOT
}

resource "google_compute_firewall" "mongodb-arbiter-firewall" {
  name = "${var.env_tag}-${var.arbiter_tag}-firewall"
  network = google_compute_network.vpc-network.name
  direction = "INGRESS"
  source_ranges = ["0.0.0.0/0"]
  target_tags = ["${var.env_tag}-${var.arbiter_tag}"]
  allow {
    protocol = "tcp"
    ports = "${var.arbiter_ports}"
  }
}
