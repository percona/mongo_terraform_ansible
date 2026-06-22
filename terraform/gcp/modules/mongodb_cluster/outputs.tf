output "hostname_shards" {
  value = [for key in local.shard_member_keys : google_compute_instance.shard[key].name]
}

output "ip_shards" {
  value = [for key in local.shard_member_keys : google_compute_instance.shard[key].network_interface[0].access_config[0].nat_ip]
}

output "ansible_group_shards" {
  value = [for key in local.shard_member_keys : google_compute_instance.shard[key].labels["ansible-group"]]
}

output "hostname_cfg" {
  value = [for key in local.cfg_member_keys : google_compute_instance.cfg[key].name]
}

output "ip_cfg" {
  value = [for key in local.cfg_member_keys : google_compute_instance.cfg[key].network_interface[0].access_config[0].nat_ip]
}

output "ansible_group_cfg" {
  value = [for key in local.cfg_member_keys : google_compute_instance.cfg[key].labels["ansible-group"]]
}

# Mongos
output "hostname_mongos" {
  value = [for key in local.mongos_member_keys : google_compute_instance.mongos[key].name]
}

output "ip_mongos" {
  value = [for key in local.mongos_member_keys : google_compute_instance.mongos[key].network_interface[0].access_config[0].nat_ip]
}

output "ansible_group_mongos" {
  value = [for key in local.mongos_member_keys : google_compute_instance.mongos[key].labels["ansible-group"]]
}

# Arbiters
output "hostname_arbiters" {
  value = [for key in local.arbiter_member_keys : google_compute_instance.arbiter[key].name]
}

output "ip_arbiters" {
  value = [for key in local.arbiter_member_keys : google_compute_instance.arbiter[key].network_interface[0].access_config[0].nat_ip]
}

output "region" {
  value = var.region
}

output "ansible_group_index" {
  value = [for key in local.shard_member_keys : google_compute_instance.shard[key].labels["ansible-index"]]
}

output "ansible_group_arb_index" {
  value = [for key in local.arbiter_member_keys : google_compute_instance.arbiter[key].labels["ansible-index"]]
}

output "ansible_group_arbiters" {
  value = [for key in local.arbiter_member_keys : google_compute_instance.arbiter[key].labels["ansible-group"]]
}

output "number_of_shards" {
  value = range(var.shard_count)
}

output "arbiters_per_replset" {
  value = var.arbiters_per_replset
}

output "gce_ssh_user" {
  value = var.my_ssh_user
}

output "cluster" {
  value = var.cluster_name
}

output "env_tag" {
  value = var.env_tag
}

output "enable_audit" {
  value = var.enable_audit
}

output "audit_filter" {
  value = var.audit_filter
}
