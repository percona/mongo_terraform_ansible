output "hostname_shards" {
  value = aws_instance.shard[*].tags["Name"]
}

output "ip_shards" {
  value = aws_instance.shard[*].public_ip
}

output "ansible_group_shards" {
  value = aws_instance.shard[*].tags["ansible-group"] 
}

output "hostname_cfg" {
  value = aws_instance.cfg[*].tags["Name"] 
}

output "ip_cfg" {
  value = aws_instance.cfg[*].public_ip 
}

output "ansible_group_cfg" {
  value = aws_instance.cfg[*].tags["ansible-group"] 
}

# Mongos
output "hostname_mongos" {
  value = aws_instance.mongos[*].tags["Name"] 
}

output "ip_mongos" {
  value = aws_instance.mongos[*].public_ip 
}

output "ansible_group_mongos" {
  value = aws_instance.mongos[*].tags["ansible-group"] 
}

# Arbiters
output "hostname_arbiters" {
  value = aws_instance.arbiter[*].tags["Name"] 
}

output "ip_arbiters" {
  value = aws_instance.arbiter[*].public_ip  
}

output "region" {
  value = var.region
}

output "ansible_group_index" {
  value = aws_instance.shard[*].tags["ansible-index"] 
}

output "ansible_group_arb_index" {
  value = aws_instance.arbiter[*].tags["ansible-index"]
}

output "ansible_group_arbiters" {
  value = aws_instance.arbiter[*].tags["ansible-group"] 
}

output "number_of_shards" {
  value = range(var.shard_count)
}

output "arbiters_per_replset" {
  value = var.arbiters_per_replset
}

output "my_ssh_user" {
  value = var.my_ssh_user
}

output "cluster" {
  value = var.cluster_name
}