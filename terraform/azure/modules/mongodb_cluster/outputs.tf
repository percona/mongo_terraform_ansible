# Shards
output "hostname_shards" {
  value = azurerm_linux_virtual_machine.shard[*].name
}

output "ip_shards" {
  value = [for vm in azurerm_linux_virtual_machine.shard : vm.public_ip_address]
}

output "ansible_group_shards" {
  value = [for vm in azurerm_linux_virtual_machine.shard : vm.tags["ansible-group"]]
}

output "ansible_group_index" {
  value = [for vm in azurerm_linux_virtual_machine.shard : vm.tags["ansible-index"]]
}

# Config servers
output "hostname_cfg" {
  value = azurerm_linux_virtual_machine.cfg[*].name
}

output "ip_cfg" {
  value = [for vm in azurerm_linux_virtual_machine.cfg : vm.public_ip_address]
}

output "ansible_group_cfg" {
  value = [for vm in azurerm_linux_virtual_machine.cfg : vm.tags["ansible-group"]]
}

# Mongos routers
output "hostname_mongos" {
  value = azurerm_linux_virtual_machine.mongos[*].name
}

output "ip_mongos" {
  value = [for vm in azurerm_linux_virtual_machine.mongos : vm.public_ip_address]
}

output "ansible_group_mongos" {
  value = [for vm in azurerm_linux_virtual_machine.mongos : vm.tags["ansible-group"]]
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

output "ansible_group_arb_index" {
  value = [for vm in azurerm_linux_virtual_machine.arbiter : vm.tags["ansible-index"]]
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