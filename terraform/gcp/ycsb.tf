resource "google_compute_instance" "ycsb" {
  count        = var.enable_ycsb ? 1 : 0
  name         = local.ycsb_host
  machine_type = var.ycsb_type
  zone         = data.google_compute_zones.available.names[0]
  tags         = [local.ycsb_host]

  boot_disk {
    initialize_params {
      image = var.image
    }
  }

  network_interface {
    network    = google_compute_network.vpc-network.id
    subnetwork = google_compute_subnetwork.vpc-subnet.id
    access_config {}
  }

  metadata = {
    ssh-keys = join("\n", [for user, key_path in var.gce_ssh_users : "${user}:${file(key_path)}"])
  }

  scheduling {
    preemptible        = false
    automatic_restart  = true
    provisioning_model = "STANDARD"
  }

  metadata_startup_script = <<EOT
    #!/bin/bash
    hostnamectl set-hostname "${local.ycsb_host}"
    echo "127.0.0.1 $(hostname) localhost" > /etc/hosts
  EOT
}

resource "google_compute_firewall" "percona-ycsb-firewall" {
  count         = var.enable_ycsb ? 1 : 0
  name          = "${local.ycsb_host}-firewall"
  network       = google_compute_network.vpc-network.name
  direction     = "INGRESS"
  source_ranges = [var.source_ranges]
  target_tags   = [local.ycsb_host]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}
