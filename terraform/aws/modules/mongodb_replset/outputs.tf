output "hostname_replsets" {
  value = aws_instance.replset[*].tags["Name"] 
}

output "ip_replsets" {
  value = aws_instance.replset[*].public_ip 
}

output "ansible_group_replsets" {
  value = aws_instance.replset[*].tags["ansible-group"] 
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

output "ansible_group_arbiters" {
  value = aws_instance.arbiter[*].tags["ansible-group"] 
}

output "data_node_count" {
  value = var.data_nodes_per_replset
}

output "arbiters_per_replset" {
  value = var.arbiters_per_replset
}

output "my_ssh_user" {
  value = var.my_ssh_user
}

output "rs_name" {
  value = var.rs_name
}

output "env_tag" {
  value = var.env_tag
}