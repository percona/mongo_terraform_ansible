output "hostname_replsets" {
  value = [for key in local.replset_member_keys : azurerm_linux_virtual_machine.replset[key].name]
}

output "ip_replsets" {
  value = [for key in local.replset_member_keys : azurerm_linux_virtual_machine.replset[key].public_ip_address]
}

output "ansible_group_replsets" {
  value = [for key in local.replset_member_keys : azurerm_linux_virtual_machine.replset[key].tags["ansible-group"]]
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

output "location" {
  value = var.location
}

output "data_node_count" {
  value = var.data_nodes_per_replset
}

output "arbiters_per_replset" {
  value = var.arbiters_per_replset
}

output "gce_ssh_user" {
  value = var.my_ssh_user
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
