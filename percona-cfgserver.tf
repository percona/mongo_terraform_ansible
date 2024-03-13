resource "google_compute_disk" "cfg_disk" {
  name  = "${var.env_tag}-mongo-cfg0${count.index}-data"
  type  = var.data_disk_type
  size  = var.configsvr_volume_size
  zone  = data.google_compute_zones.available.names[count.index % 3]
  count = var.configsvr_count
}

resource "google_compute_instance" "cfg" {
  name = "${var.env_tag}-mongo-cfg0${count.index}"
  machine_type = var.configsvr_type
  zone  = data.google_compute_zones.available.names[count.index % 3]
  count = var.configsvr_count
  tags = ["mongodb-cfg"]
  labels = { 
    ansible-group = "cfg",
    environment = var.env_tag
  }  
  boot_disk {
    initialize_params {
    image = lookup(var.centos_amis, var.region)
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
    ssh-keys = "${var.gce_ssh_user}:${file(var.gce_ssh_pub_key_file)}"
  }
  metadata_startup_script = <<EOT
    #! /bin/bash
    echo "Created"
EOT
}

resource "google_compute_firewall" "mongodb-cfgsvr-firewall" {
  name = "${var.env_tag}-mongodb-cfgsvr-firewall"
  network = google_compute_network.vpc-network.name
  direction = "INGRESS"
  source_ranges = ["0.0.0.0/0"]
  target_tags = ["mongodb-cfg"]
  allow {
    protocol = "tcp"
    ports = ["22", "27019"]
 }
}

