resource "google_compute_disk" "cfg_disk" {
  name  = "${var.cluster_name}-${var.configsvr_tag}0${count.index}-data"
  type  = var.data_disk_type
  size  = var.configsvr_volume_size
  zone  = data.google_compute_zones.available.names[count.index % length(data.google_compute_zones.available.names)]
  count = var.configsvr_count
}

resource "google_compute_instance" "cfg" {
  name = "${var.cluster_name}-${var.configsvr_tag}0${count.index}"
  machine_type = var.configsvr_type
  zone  = data.google_compute_zones.available.names[count.index % length(data.google_compute_zones.available.names)]
  count = var.configsvr_count
  tags = ["${var.cluster_name}-${var.configsvr_tag}"]
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
    hostnamectl set-hostname "${var.cluster_name}-${var.configsvr_tag}0${count.index}"

    # Update /etc/hosts to reflect the hostname change
    echo "127.0.0.1 $(hostname)" >> /etc/hosts    

    DEVICE=$(readlink -f /dev/disk/by-id/google-persistent-disk-1)            

    mkfs.xfs $DEVICE

    mkdir -p /var/lib/mongo

    mount $DEVICE /var/lib/mongo

    UUID=$(blkid -s UUID -o value "$DEVICE")
    echo "UUID=$UUID /var/lib/mongo xfs defaults,noatime,nofail 0 2" >> /etc/fstab
  EOT
}

resource "google_compute_firewall" "mongodb-cfgsvr-firewall" {
  name = "${var.cluster_name}-${var.configsvr_tag}-firewall"
  network = var.vpc
  direction = "INGRESS"
  source_ranges = ["${var.subnet_cidr}"]
  target_tags = ["${var.cluster_name}-${var.configsvr_tag}"]
  allow {
    protocol = "tcp"
    ports = "${var.configsvr_ports}"
  }
}
