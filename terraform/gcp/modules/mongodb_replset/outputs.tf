output "hostname_replsets" {
  value = [for key in local.replset_member_keys : google_compute_instance.replset[key].name]
}

output "ip_replsets" {
  value = [for key in local.replset_member_keys : google_compute_instance.replset[key].network_interface[0].access_config[0].nat_ip]
}

output "ansible_group_replsets" {
  value = [for key in local.replset_member_keys : google_compute_instance.replset[key].labels["ansible-group"]]
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

output "ansible_group_arbiters" {
  value = [for key in local.arbiter_member_keys : google_compute_instance.arbiter[key].labels["ansible-group"]]
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
