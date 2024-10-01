resource "google_compute_disk" "shard_disk" {
  name  = "${var.env_tag}-${var.shardsvr_tag}0${floor(count.index / var.shardsvr_replicas )}svr${count.index % var.shardsvr_replicas}-data"
  type  = var.data_disk_type
  size  = var.shardsvr_volume_size
  zone  = data.google_compute_zones.available.names[count.index % length(data.google_compute_zones.available.names) % var.shardsvr_replicas]
  count = var.shard_count * var.shardsvr_replicas
}

resource "google_compute_instance" "shard" {
  name = "${var.env_tag}-${var.shardsvr_tag}0${floor(count.index / var.shardsvr_replicas )}svr${count.index % var.shardsvr_replicas}"
  machine_type = var.shardsvr_type
  zone  = data.google_compute_zones.available.names[count.index % length(data.google_compute_zones.available.names) % var.shardsvr_replicas]
  count = var.shard_count * var.shardsvr_replicas
  tags = ["${var.env_tag}-${var.shardsvr_tag}"]
  labels = { 
    ansible-group = floor(count.index / var.shardsvr_replicas ),
    ansible-index = count.index % var.shardsvr_replicas,
    environment = var.env_tag
  }  
  boot_disk {
    initialize_params {
    image = lookup(var.image, var.region)
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
    hostnamectl set-hostname "${var.env_tag}-${var.shardsvr_tag}0${floor(count.index / var.shardsvr_replicas)}svr${count.index % var.shardsvr_replicas}.${var.env_tag}"

    # Update /etc/hosts to reflect the hostname change
    echo "127.0.0.1 $(hostname)" >> /etc/hosts    

    # Add a dash to lsblk output to match the Terraform volume ID 
    DEVICE=$(lsblk -o NAME,SERIAL | sed 's/l/l-/' | grep "${google_compute_disk.shard_disk[count.index].id}" | awk '{print "/dev/" $1}')

    mkfs.xfs $DEVICE

    mkdir -p /var/lib/mongo

    mount $DEVICE /var/lib/mongo

    UUID=$(blkid -s UUID -o value "$DEVICE")
    echo "UUID=$DEVICE /var/lib/mongo xfs defaults,noatime,nofail 0 2" >> /etc/fstab    

  EOT
}

resource "google_compute_firewall" "mongodb-shardsvr-firewall" {
  name = "${var.env_tag}-${var.shardsvr_tag}-firewall"
  network = google_compute_network.vpc-network.name
  direction = "INGRESS"
  source_ranges = ["0.0.0.0/0"]
  target_tags = ["${var.env_tag}-${var.shardsvr_tag}"]
  allow {
    protocol = "tcp"
    ports = "${var.shard_ports}"
  }
}
