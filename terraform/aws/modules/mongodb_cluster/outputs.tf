output "hostname_shards" {
  value = [for key in local.shard_member_keys : aws_instance.shard[key].tags["Name"]]
}

output "ip_shards" {
  value = [for key in local.shard_member_keys : aws_instance.shard[key].public_ip]
}

output "ansible_group_shards" {
  value = [for key in local.shard_member_keys : aws_instance.shard[key].tags["ansible-group"]]
}

output "hostname_cfg" {
  value = [for key in local.cfg_member_keys : aws_instance.cfg[key].tags["Name"]]
}

output "ip_cfg" {
  value = [for key in local.cfg_member_keys : aws_instance.cfg[key].public_ip]
}

output "ansible_group_cfg" {
  value = [for key in local.cfg_member_keys : aws_instance.cfg[key].tags["ansible-group"]]
}

# Mongos
output "hostname_mongos" {
  value = [for key in local.mongos_member_keys : aws_instance.mongos[key].tags["Name"]]
}

output "ip_mongos" {
  value = [for key in local.mongos_member_keys : aws_instance.mongos[key].public_ip]
}

output "ansible_group_mongos" {
  value = [for key in local.mongos_member_keys : aws_instance.mongos[key].tags["ansible-group"]]
}

# Arbiters
output "hostname_arbiters" {
  value = [for key in local.arbiter_member_keys : aws_instance.arbiter[key].tags["Name"]]
}

output "ip_arbiters" {
  value = [for key in local.arbiter_member_keys : aws_instance.arbiter[key].public_ip]
}

output "region" {
  value = var.region
}

output "ansible_group_index" {
  value = [for key in local.shard_member_keys : aws_instance.shard[key].tags["ansible-index"]]
}

output "ansible_group_arbiters" {
  value = [for key in local.arbiter_member_keys : aws_instance.arbiter[key].tags["ansible-group"]]
}

output "number_of_shards" {
  value = range(var.shard_count)
}

output "my_ssh_user" {
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
