resource "google_compute_instance" "arbiter" {
  name  = "${var.cluster_name}-${var.shardsvr_tag}0${floor(count.index / var.arbiters_per_replset)}arb${count.index % var.arbiters_per_replset}"
  machine_type = var.arbiter_type
  zone  = data.google_compute_zones.available.names[count.index % length(data.google_compute_zones.available.names) % var.arbiters_per_replset]
  count = var.shard_count * var.arbiters_per_replset
  tags = ["${var.cluster_name}-${var.arbiter_tag}"]
  labels = { 
    ansible-group = floor(count.index / var.arbiters_per_replset),
    ansible-index = count.index % var.arbiters_per_replset,
    environment = var.env_tag
  }  
  boot_disk {
    initialize_params {
    image = lookup(var.image, var.region)
    }
  }   
  network_interface {
    network = var.vpc
    subnetwork = var.subnet_name
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
    #!/bin/bash
    # Set the hostname
    hostnamectl set-hostname "${var.cluster_name}-${var.shardsvr_tag}0${floor(count.index / var.arbiters_per_replset )}arb${count.index % var.arbiters_per_replset}"

    # Update /etc/hosts to reflect the hostname change
    echo "127.0.0.1 $(hostname)" >> /etc/hosts    
  EOT
}

resource "google_compute_firewall" "mongodb-arbiter-firewall" {
  name = "${var.cluster_name}-${var.arbiter_tag}-firewall"
  network = var.vpc
  direction = "INGRESS"
  source_ranges = ["${var.subnet_cidr}"]
  target_tags = ["${var.cluster_name}-${var.arbiter_tag}"]
  allow {
    protocol = "tcp"
    ports = "${var.arbiter_ports}"
  }
}
