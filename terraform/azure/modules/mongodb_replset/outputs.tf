output "hostname_replsets" {
  value = azurerm_linux_virtual_machine.replset[*].name
}

output "ip_replsets" {
  value = [for vm in azurerm_linux_virtual_machine.replset : vm.public_ip_address]
}

output "ansible_group_replsets" {
  value = [for vm in azurerm_linux_virtual_machine.replset : vm.tags["ansible-group"]]
}

# Arbiters
output "hostname_arbiters" {
  value = azurerm_linux_virtual_machine.arbiter[*].name
}

output "ip_arbiters" {
  value = [for vm in azurerm_linux_virtual_machine.arbiter : vm.public_ip_address]
}

output "ansible_group_arbiters" {
  value = [for vm in azurerm_linux_virtual_machine.arbiter : vm.tags["ansible-group"]]
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