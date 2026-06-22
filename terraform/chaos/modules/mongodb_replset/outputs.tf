output "hostname_replsets" {
  value = [for key in local.replset_member_keys : chaos_instance.replset[key].name]
}

output "ip_replsets" {
  value = [for key in local.replset_member_keys : chaos_instance.replset[key].ip_address]
}

output "ansible_group_replsets" {
  value = [for i in range(var.data_nodes_per_replset) : var.replset_tag]
}

output "hostname_arbiters" {
  value = [for key in local.arbiter_member_keys : chaos_instance.arbiter[key].name]
}

output "ip_arbiters" {
  value = [for key in local.arbiter_member_keys : chaos_instance.arbiter[key].ip_address]
}

output "ansible_group_arbiters" {
  value = [for i in range(var.arbiters_per_replset) : var.replset_tag]
}

output "data_node_count" {
  value = var.data_nodes_per_replset
}

output "arbiters_per_replset" {
  value = var.arbiters_per_replset
}

output "rs_name" {
  value = var.rs_name
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
