output "hostname_shards" {
  value = chaos_instance.shard[*].name
}

output "ip_shards" {
  value = chaos_instance.shard[*].ip_address
}

output "ansible_group_shards" {
  value = [for i in range(var.shard_count * var.shardsvr_replicas) : tostring(floor(i / var.shardsvr_replicas))]
}

output "ansible_group_index" {
  value = [for i in range(var.shard_count * var.shardsvr_replicas) : tostring(i % var.shardsvr_replicas)]
}

output "hostname_cfg" {
  value = chaos_instance.cfg[*].name
}

output "ip_cfg" {
  value = chaos_instance.cfg[*].ip_address
}

output "ansible_group_cfg" {
  value = [for i in range(var.configsvr_count) : "cfg"]
}

output "hostname_mongos" {
  value = chaos_instance.mongos[*].name
}

output "ip_mongos" {
  value = chaos_instance.mongos[*].ip_address
}

output "ansible_group_mongos" {
  value = [for i in range(var.mongos_count) : "mongos"]
}

output "hostname_arbiters" {
  value = chaos_instance.arbiter[*].name
}

output "ip_arbiters" {
  value = chaos_instance.arbiter[*].ip_address
}

output "ansible_group_arbiters" {
  value = [for i in range(var.shard_count * var.arbiters_per_replset) : tostring(floor(i / var.arbiters_per_replset))]
}

output "ansible_group_arb_index" {
  value = [for i in range(var.shard_count * var.arbiters_per_replset) : tostring(i % var.arbiters_per_replset)]
}

output "number_of_shards" {
  value = range(var.shard_count)
}

output "arbiters_per_replset" {
  value = var.arbiters_per_replset
}

output "cluster" {
  value = var.cluster_name
}

output "env_tag" {
  value = var.env_tag
}
