resource "google_compute_disk" "cfg_disk" {
  name  = "${var.env_tag}-${var.configsvr_tag}0${count.index}-data"
  type  = var.data_disk_type
  size  = var.configsvr_volume_size
  zone  = data.google_compute_zones.available.names[count.index % length(data.google_compute_zones.available.names)]
  count = var.configsvr_count
}

resource "google_compute_instance" "cfg" {
  name = "${var.env_tag}-${var.configsvr_tag}0${count.index}"
  machine_type = var.configsvr_type
  zone  = data.google_compute_zones.available.names[count.index % length(data.google_compute_zones.available.names)]
  count = var.configsvr_count
  tags = ["${var.env_tag}-${var.configsvr_tag}"]
  labels = { 
    ansible-group = "cfg",
    environment = var.env_tag
  }  
  boot_disk {
    initialize_params {
    image = lookup(var.image, var.region)
    }
  }
  attached_disk {
    source = element(google_compute_disk.cfg_disk.*.self_link, count.index)
  }   
  network_interface {
    network = google_compute_network.vpc-network.id
    subnetwork = google_compute_subnetwork.vpc-subnet.id
    access_config {}
  }
  metadata = {
    ssh-keys = join("\n", [for user, key_path in var.gce_ssh_users : "${user}:${file(key_path)}"])
  }
  metadata_startup_script = <<EOT
    #! /bin/bash
    echo "Created"
EOT
}

resource "google_compute_firewall" "mongodb-cfgsvr-firewall" {
  name = "${var.env_tag}-${var.configsvr_tag}-firewall"
  network = google_compute_network.vpc-network.name
  direction = "INGRESS"
  source_ranges = ["0.0.0.0/0"]
  target_tags = ["${var.env_tag}-${var.configsvr_tag}"]
  allow {
    protocol = "tcp"
    ports = "${var.configsvr_ports}"
  }
}
