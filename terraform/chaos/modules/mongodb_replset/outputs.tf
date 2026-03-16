output "hostname_replsets" {
  value = chaos_instance.replset[*].name
}

output "ip_replsets" {
  value = chaos_instance.replset[*].ip_address
}

output "ansible_group_replsets" {
  value = [for i in range(var.data_nodes_per_replset) : var.replset_tag]
}

output "hostname_arbiters" {
  value = chaos_instance.arbiter[*].name
}

output "ip_arbiters" {
  value = chaos_instance.arbiter[*].ip_address
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
