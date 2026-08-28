output "hostname_shards" {
  value = [for key in local.shard_member_keys : chaos_instance.shard[key].name]
}

output "ip_shards" {
  value = [for key in local.shard_member_keys : chaos_instance.shard[key].ip_address]
}

output "ansible_group_shards" {
  value = [for key in local.shard_member_keys : tostring(local.shard_members[key].shard_index)]
}

output "ansible_group_index" {
  value = [for key in local.shard_member_keys : tostring(local.shard_members[key].replica_index)]
}

output "hostname_cfg" {
  value = [for key in local.cfg_member_keys : chaos_instance.cfg[key].name]
}

output "ip_cfg" {
  value = [for key in local.cfg_member_keys : chaos_instance.cfg[key].ip_address]
}

output "ansible_group_cfg" {
  value = [for i in range(var.configsvr_count) : "cfg"]
}

output "hostname_mongos" {
  value = [for key in local.mongos_member_keys : chaos_instance.mongos[key].name]
}

output "ip_mongos" {
  value = [for key in local.mongos_member_keys : chaos_instance.mongos[key].ip_address]
}

output "ansible_group_mongos" {
  value = [for i in range(var.mongos_count) : "mongos"]
}

output "hostname_arbiters" {
  value = [for key in local.arbiter_member_keys : chaos_instance.arbiter[key].name]
}

output "ip_arbiters" {
  value = [for key in local.arbiter_member_keys : chaos_instance.arbiter[key].ip_address]
}

output "ansible_group_arbiters" {
  value = [for key in local.arbiter_member_keys : tostring(local.arbiter_members[key].shard_index)]
}

output "number_of_shards" {
  value = range(var.shard_count)
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
