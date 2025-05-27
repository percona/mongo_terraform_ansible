output "hostname_shards" {
  value = google_compute_instance.shard[*].name
}

output "ip_shards" {
  value = google_compute_instance.shard[*].network_interface[0].access_config[0].nat_ip
}

output "ansible_group_shards" {
  value = [for i in google_compute_instance.shard : i.labels["ansible-group"]]
}

output "hostname_cfg" {
  value = google_compute_instance.cfg[*].name
}

output "ip_cfg" {
  value = google_compute_instance.cfg[*].network_interface[0].access_config[0].nat_ip
}

output "ansible_group_cfg" {
  value = [for i in google_compute_instance.cfg : i.labels["ansible-group"]]
}

# Mongos
output "hostname_mongos" {
  value = google_compute_instance.mongos[*].name
}

output "ip_mongos" {
  value = google_compute_instance.mongos[*].network_interface[0].access_config[0].nat_ip
}

output "ansible_group_mongos" {
  value = [for i in google_compute_instance.mongos : i.labels["ansible-group"]]
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

output "ansible_group_index" {
  value = [for i in google_compute_instance.shard : i.labels["ansible-index"]]
}

output "ansible_group_arb_index" {
  value = [for i in google_compute_instance.arbiter : i.labels["ansible-index"]]
}

output "ansible_group_arbiters" {
  value = [for i in google_compute_instance.arbiter : i.labels["ansible-group"]]
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