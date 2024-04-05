### The Ansible inventory file
resource "local_file" "AnsibleInventory" {
  content = templatefile("inventory.tmpl",
    {
     ansible_group_shards = google_compute_instance.shard.*.labels.ansible-group,
     ansible_group_index = google_compute_instance.shard.*.labels.ansible-index,
     hostname_shards = google_compute_instance.shard.*.name,
     ip_shards = google_compute_instance.shard.*.network_interface.0.access_config.0.nat_ip,
     ansible_group_cfg = google_compute_instance.cfg.*.labels.ansible-group,
     hostname_cfg = google_compute_instance.cfg.*.name,
     ip_cfg = google_compute_instance.cfg.*.network_interface.0.access_config.0.nat_ip,
     ansible_group_mongos = google_compute_instance.mongos.*.labels.ansible-group,
     hostname_mongos = google_compute_instance.mongos.*.name,
     ip_mongos = google_compute_instance.mongos.*.network_interface.0.access_config.0.nat_ip,
     number_of_shards = range(var.shard_count),
     gce_ssh_user = var.my_ssh_user
     hostname_pmm = google_compute_instance.pmm.name,
     public_ip_pmm = google_compute_instance.pmm.network_interface.0.access_config.0.nat_ip,
     private_ip_pmm = google_compute_instance.pmm.network_interface.0.network_ip,
     bucket = google_storage_bucket.mongo-backups.name,
     region = google_storage_bucket.mongo-backups.location,
     cluster = var.env_tag,
     access_key = google_storage_hmac_key.mongo-backup-service-account.access_id,
     secret_access_key = google_storage_hmac_key.mongo-backup-service-account.secret,
    }
  )
  filename = "inventory"
}

### The ssh config file
resource "local_file" "SSHConfig" {
  content = templatefile("ssh_config.tmpl",
    {
     ansible_group_shards = google_compute_instance.shard.*.labels.ansible-group,
     hostname_shards = google_compute_instance.shard.*.name,
     ip_shards = google_compute_instance.shard.*.network_interface.0.access_config.0.nat_ip,
     ansible_group_cfg = google_compute_instance.cfg.*.labels.ansible-group,
     hostname_cfg = google_compute_instance.cfg.*.name,
     ip_cfg = google_compute_instance.cfg.*.network_interface.0.access_config.0.nat_ip,
     ansible_group_mongos = google_compute_instance.mongos.*.labels.ansible-group,
     hostname_mongos = google_compute_instance.mongos.*.name,
     ip_mongos = google_compute_instance.mongos.*.network_interface.0.access_config.0.nat_ip,
     gce_ssh_user = var.my_ssh_user
     hostname_pmm = google_compute_instance.pmm.name,
     public_ip_pmm = google_compute_instance.pmm.network_interface.0.access_config.0.nat_ip,
     enable_ssh_gateway = var.enable_ssh_gateway,
    }
  )
  filename = "ssh_config"
}
