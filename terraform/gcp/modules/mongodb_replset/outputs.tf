output "hostname_replsets" {
  value = google_compute_instance.replset[*].name
}

output "ip_replsets" {
  value = google_compute_instance.replset[*].network_interface[0].access_config[0].nat_ip
}

output "ansible_group_replsets" {
  value = [for i in google_compute_instance.replset : i.labels["ansible-group"]]
}

# Arbiters
output "hostname_arbiters" {
  value = google_compute_instance.arbiter[*].name
}

output "ip_arbiters" {
  value = google_compute_instance.arbiter[*].network_interface[0].access_config[0].nat_ip
}

output "region" {
  value = var.region
}

output "ansible_group_arbiters" {
  value = [for i in google_compute_instance.arbiter : i.labels["ansible-group"]]
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