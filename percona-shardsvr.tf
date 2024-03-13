resource "google_compute_disk" "shard_disk" {
  name  = "${var.env_tag}-mongo-shard0${floor(count.index / var.shardsvr_replicas )}svr${count.index % var.shardsvr_replicas}-data"
  type  = var.data_disk_type
  size  = var.shardsvr_volume_size
  zone  = data.google_compute_zones.available.names[count.index % var.shardsvr_replicas]
  count = var.shard_count * var.shardsvr_replicas
}

resource "google_compute_instance" "shard" {
  name = "${var.env_tag}-mongo-shard0${floor(count.index / var.shardsvr_replicas )}svr${count.index % var.shardsvr_replicas}"
  machine_type = var.shardsvr_type
  zone  = data.google_compute_zones.available.names[count.index % var.shardsvr_replicas]
  count = var.shard_count * var.shardsvr_replicas
  tags = ["mongodb-shard"]
  labels = { 
    ansible-group = floor(count.index / var.shardsvr_replicas ),
    ansible-index = count.index % var.shardsvr_replicas,
    environment = var.env_tag
  }  
  boot_disk {
    initialize_params {
    image = lookup(var.centos_amis, var.region)
    }
  }   
  attached_disk {
    source = element(google_compute_disk.shard_disk.*.self_link, count.index)
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
resource "google_compute_firewall" "mongodb-shardsvr-firewall" {
  name = "${var.env_tag}-mongodb-shardsvr-firewall"
  network = google_compute_network.vpc-network.name
  direction = "INGRESS"
  source_ranges = ["0.0.0.0/0"]
  target_tags = ["${var.env_tag}-mongodb-shard"]
  allow {
    protocol = "tcp"
    ports = ["22", "27017", "27018"]
 }
}
