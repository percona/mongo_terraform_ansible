# The benchmark client shares the hardware tunables of the MongoDB nodes (boot disk,
# CPU platform, NIC, placement) and sits in the first zone, next to replica index 0
# of every shard/replica set. It never runs on spot capacity.
resource "google_compute_instance" "ycsb" {
  count                     = var.enable_ycsb ? 1 : 0
  name                      = local.ycsb_host
  machine_type              = var.ycsb_type
  min_cpu_platform          = var.min_cpu_platform
  resource_policies         = local.placement_policies
  allow_stopping_for_update = true
  zone                      = local.zones[0]
  tags                      = [local.ycsb_host]
  labels                    = var.labels

  boot_disk {
    initialize_params {
      image = var.image
      size  = var.boot_disk_size
      type  = var.boot_disk_type
    }
  }

  network_interface {
    network    = google_compute_network.vpc-network.id
    subnetwork = google_compute_subnetwork.vpc-subnet.id
    nic_type   = var.nic_type
    access_config {}
  }

  dynamic "network_performance_config" {
    for_each = var.tier1_networking ? [1] : []
    content {
      total_egress_bandwidth_tier = "TIER_1"
    }
  }

  metadata = {
    ssh-keys = join("\n", [for user, key_path in var.gce_ssh_users : "${user}:${file(key_path)}"])
  }

  scheduling {
    preemptible         = false
    automatic_restart   = true
    provisioning_model  = "STANDARD"
    on_host_maintenance = var.compact_placement ? "TERMINATE" : "MIGRATE"
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
