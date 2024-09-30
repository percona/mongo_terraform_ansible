resource "local_file" "AnsibleInventory" {
  content = templatefile("inventory.tmpl",
    {
     ansible_group_shards = aws_instance.shard[*].tags["ansible-group"],
     ansible_group_index = aws_instance.shard[*].tags["ansible-index"],
     hostname_shards = aws_instance.shard[*].tags["Name"],
     ip_shards = aws_instance.shard[*].public_ip,
     ansible_group_cfg = aws_instance.cfg[*].tags["ansible-group"],
     hostname_cfg = aws_instance.cfg[*].tags["Name"],
     ip_cfg = aws_instance.cfg[*].public_ip,
     ansible_group_mongos = aws_instance.mongos[*].tags["ansible-group"],
     hostname_mongos = aws_instance.mongos[*].tags["Name"],
     ip_mongos = aws_instance.mongos[*].public_ip,
     ansible_group_arbiters = aws_instance.arbiter[*].tags["ansible-group"],
     ansible_group_arb_index = aws_instance.arbiter[*].tags["ansible-index"],     
     hostname_arbiters = aws_instance.arbiter[*].tags["Name"],
     ip_arbiters = aws_instance.arbiter[*].public_ip,     
     number_of_shards = range(var.shard_count),
     arbiters_per_replset = range(var.arbiters_per_replset),
     my_ssh_user = var.my_ssh_user,
     hostname_pmm = aws_instance.pmm.tags["Name"],
     public_ip_pmm = aws_instance.pmm.public_ip,
     private_ip_pmm = aws_instance.pmm.private_ip,
     bucket = aws_s3_bucket.mongo_backups.bucket,
     region = aws_s3_bucket.mongo_backups.region,
     endpointUrl = "https://s3.${var.region}.amazonaws.com",
     cluster = var.env_tag,
     access_key = aws_iam_access_key.mongo_backup_access_key.id,
     secret_access_key = aws_iam_access_key.mongo_backup_access_key.secret
    }
  )
  filename = "inventory"
}

resource "local_file" "SSHConfig" {
  content = templatefile("ssh_config.tmpl",
    {
     ansible_group_shards = aws_instance.shard[*].tags["ansible-group"],
     hostname_shards = aws_instance.shard[*].tags["Name"],
     ip_shards = aws_instance.shard[*].public_ip,
     ansible_group_cfg = aws_instance.cfg[*].tags["ansible-group"],
     hostname_cfg = aws_instance.cfg[*].tags["Name"],
     ip_cfg = aws_instance.cfg[*].public_ip,
     ansible_group_mongos = aws_instance.mongos[*].tags["ansible-group"],
     hostname_mongos = aws_instance.mongos[*].tags["Name"],
     ip_mongos = aws_instance.mongos[*].public_ip,
     hostname_arbiters = aws_instance.arbiter[*].tags["Name"],
     ip_arbiters = aws_instance.arbiter[*].public_ip,          
     my_ssh_user = var.my_ssh_user,
     hostname_pmm = aws_instance.pmm.tags["Name"],
     public_ip_pmm = aws_instance.pmm.public_ip,
     enable_ssh_gateway = var.enable_ssh_gateway
    }
  )
  filename = "ssh_config"
}