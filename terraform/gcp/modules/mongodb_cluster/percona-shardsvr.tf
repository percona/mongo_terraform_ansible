locals {
  shard_members = {
    for member in flatten([
      for shard_index in range(var.shard_count) : [
        for replica_index in range(var.shardsvr_replicas) : {
          key           = "shard${shard_index}svr${replica_index}"
          shard_index   = shard_index
          replica_index = replica_index
        }
      ]
    ]) : member.key => member
  }

  shard_member_keys = flatten([
    for shard_index in range(var.shard_count) : [
      for replica_index in range(var.shardsvr_replicas) : "shard${shard_index}svr${replica_index}"
    ]
  ])

  cfg_members        = { for cfg_index in range(var.configsvr_count) : "cfg${cfg_index}" => cfg_index }
  cfg_member_keys    = [for cfg_index in range(var.configsvr_count) : "cfg${cfg_index}"]
  mongos_members     = { for mongos_index in range(var.mongos_count) : "mongos${mongos_index}" => mongos_index }
  mongos_member_keys = [for mongos_index in range(var.mongos_count) : "mongos${mongos_index}"]

  arbiter_members = {
    for member in flatten([
      for shard_index in range(var.shard_count) : [
        for arbiter_index in range(var.arbiters_per_replset) : {
          key           = "shard${shard_index}arb${arbiter_index}"
          shard_index   = shard_index
          arbiter_index = arbiter_index
        }
      ]
    ]) : member.key => member
  }

  arbiter_member_keys = flatten([
    for shard_index in range(var.shard_count) : [
      for arbiter_index in range(var.arbiters_per_replset) : "shard${shard_index}arb${arbiter_index}"
    ]
  ])
}

resource "google_compute_disk" "shard_disk" {
  for_each = local.shard_members
  name     = "${var.cluster_name}-${var.shardsvr_tag}0${each.value.shard_index}svr${each.value.replica_index}-data"
  type     = var.data_disk_type
  size     = var.shardsvr_volume_size
  zone     = data.google_compute_zones.available.names[each.value.replica_index % length(data.google_compute_zones.available.names)]
}

resource "google_compute_instance" "shard" {
  for_each     = local.shard_members
  name         = "${var.cluster_name}-${var.shardsvr_tag}0${each.value.shard_index}svr${each.value.replica_index}"
  machine_type = var.shardsvr_type
  zone         = data.google_compute_zones.available.names[each.value.replica_index % length(data.google_compute_zones.available.names)]
  tags         = ["${var.cluster_name}-${var.shardsvr_tag}"]
  labels = {
    ansible-group = tostring(each.value.shard_index),
    ansible-index = tostring(each.value.replica_index),
    environment   = var.env_tag
  }
  boot_disk {
    initialize_params {
      image = var.image
    }
  }
  attached_disk {
    source = google_compute_disk.shard_disk[each.key].self_link
  }
  network_interface {
    network    = var.vpc
    subnetwork = var.subnet_name
    access_config {}
  }
  metadata = {
    ssh-keys = join("\n", [for user, key_path in var.gce_ssh_users : "${user}:${file(key_path)}"])
  }
  scheduling {
    preemptible        = var.use_spot_instances
    automatic_restart  = var.use_spot_instances ? false : true
    provisioning_model = var.use_spot_instances ? "SPOT" : "STANDARD"
  }
  metadata_startup_script = <<EOT
    #!/bin/bash
    # Set the hostname
    hostnamectl set-hostname "${var.cluster_name}-${var.shardsvr_tag}0${each.value.shard_index}svr${each.value.replica_index}"

    # Update /etc/hosts to reflect the hostname change
    echo "127.0.0.1 $(hostname) localhost" > /etc/hosts    

    DEVICE=$(readlink -f /dev/disk/by-id/google-persistent-disk-1)            

    mkfs.xfs $DEVICE

    mkdir -p /var/lib/mongo

    mount $DEVICE /var/lib/mongo

    UUID=$(blkid -s UUID -o value "$DEVICE")
    echo "UUID=$DEVICE /var/lib/mongo xfs defaults,noatime,nofail 0 2" >> /etc/fstab    

  EOT
}

resource "google_compute_firewall" "mongodb-shardsvr-firewall" {
  name          = "${var.cluster_name}-${var.shardsvr_tag}-firewall"
  network       = var.vpc
  direction     = "INGRESS"
  source_ranges = ["${var.subnet_cidr}"]
  target_tags   = ["${var.cluster_name}-${var.shardsvr_tag}"]
  allow {
    protocol = "tcp"
    ports    = [var.shard_port]
  }
}
