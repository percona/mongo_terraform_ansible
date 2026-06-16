# Shards
output "hostname_shards" {
  value = [for key in local.shard_member_keys : azurerm_linux_virtual_machine.shard[key].name]
}

output "ip_shards" {
  value = [for key in local.shard_member_keys : azurerm_linux_virtual_machine.shard[key].public_ip_address]
}

output "ansible_group_shards" {
  value = [for key in local.shard_member_keys : azurerm_linux_virtual_machine.shard[key].tags["ansible-group"]]
}

output "ansible_group_index" {
  value = [for key in local.shard_member_keys : azurerm_linux_virtual_machine.shard[key].tags["ansible-index"]]
}

# Config servers
output "hostname_cfg" {
  value = [for key in local.cfg_member_keys : azurerm_linux_virtual_machine.cfg[key].name]
}

output "ip_cfg" {
  value = [for key in local.cfg_member_keys : azurerm_linux_virtual_machine.cfg[key].public_ip_address]
}

output "ansible_group_cfg" {
  value = [for key in local.cfg_member_keys : azurerm_linux_virtual_machine.cfg[key].tags["ansible-group"]]
}

# Mongos routers
output "hostname_mongos" {
  value = [for key in local.mongos_member_keys : azurerm_linux_virtual_machine.mongos[key].name]
}

output "ip_mongos" {
  value = [for key in local.mongos_member_keys : azurerm_linux_virtual_machine.mongos[key].public_ip_address]
}

output "ansible_group_mongos" {
  value = [for key in local.mongos_member_keys : azurerm_linux_virtual_machine.mongos[key].tags["ansible-group"]]
}

# Arbiters
output "hostname_arbiters" {
  value = [for key in local.arbiter_member_keys : azurerm_linux_virtual_machine.arbiter[key].name]
}

output "ip_arbiters" {
  value = [for key in local.arbiter_member_keys : azurerm_linux_virtual_machine.arbiter[key].public_ip_address]
}

output "ansible_group_arbiters" {
  value = [for key in local.arbiter_member_keys : azurerm_linux_virtual_machine.arbiter[key].tags["ansible-group"]]
}

output "ansible_group_arb_index" {
  value = [for key in local.arbiter_member_keys : azurerm_linux_virtual_machine.arbiter[key].tags["ansible-index"]]
}

# Cluster-wide information
output "location" {
  value = var.location
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
