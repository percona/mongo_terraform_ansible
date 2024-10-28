### The Ansible inventory file
resource "local_file" "AnsibleInventory" {
  content = templatefile("inventory.tmpl",
    {
     ansible_group_shards = [
       for instance in docker_container.shard :
       lookup({for label in instance.labels : label.label => label.value}, "ansible-group", null)
     ],
     ansible_group_index = [
       for instance in docker_container.shard :
       lookup({for label in instance.labels : label.label => label.value}, "ansible-index", null)
     ],     
     hostname_shards = docker_container.shard.*.name,
     ip_shards = [for instance in docker_container.shard : instance.network_data[0].ip_address],
     ansible_group_cfg = [
       for instance in docker_container.cfg :
       lookup({for label in instance.labels : label.label => label.value}, "ansible-group", null)
     ],     
     hostname_cfg = docker_container.cfg.*.name,
     ip_cfg = [for instance in docker_container.cfg : instance.network_data[0].ip_address],
     ansible_group_mongos = [
       for instance in docker_container.mongos :
       lookup({for label in instance.labels : label.label => label.value}, "ansible-group", null)
     ],     
     hostname_mongos = docker_container.mongos.*.name,
     ip_mongos = [for instance in docker_container.mongos : instance.network_data[0].ip_address],
     ansible_group_arbiters = [
       for instance in docker_container.arbiter :
       lookup({for label in instance.labels : label.label => label.value}, "ansible-group", null)
     ],     
     ansible_group_arb_index = [
       for instance in docker_container.arbiter :
       lookup({for label in instance.labels : label.label => label.value}, "ansible-group", null)
     ],     
     hostname_arbiters = docker_container.arbiter.*.name,
     ip_arbiters = [for instance in docker_container.arbiter : instance.network_data[0].ip_address],
     number_of_shards = range(var.shard_count),
     arbiters_per_replset = range(var.arbiters_per_replset),
     ssh_user = var.my_ssh_user,
     hostname_pmm = docker_container.pmm.name,
     public_ip_pmm = docker_container.pmm.network_data[0].ip_address,
     private_ip_pmm = docker_container.pmm.network_data[0].ip_address,
     bucket = var.bucket_name,
     region = var.minio_region,
     endpointUrl = "https://storage.googleapis.com",
     cluster = var.env_tag,
     access_key = var.minio_access_key,
     secret_access_key = var.minio_secret_key
    }
  )
  filename = "inventory"
}

### The ssh config file
resource "local_file" "SSHConfig" {
  content = templatefile("ssh_config.tmpl",
    {
     ansible_group_shards = [
       for instance in docker_container.shard :
       lookup({for label in instance.labels : label.label => label.value}, "ansible-group", null)
     ],     
     hostname_shards = docker_container.shard.*.name,
     ip_shards = [for instance in docker_container.shard : instance.network_data[0].ip_address],
     ansible_group_cfg = [
       for instance in docker_container.cfg :
       lookup({for label in instance.labels : label.label => label.value}, "ansible-group", null)
     ],     
     hostname_cfg = docker_container.cfg.*.name,
     ip_cfg = [for instance in docker_container.cfg : instance.network_data[0].ip_address],
     ansible_group_mongos = [
       for instance in docker_container.mongos :
       lookup({for label in instance.labels : label.label => label.value}, "ansible-group", null)
     ],     
     hostname_mongos = docker_container.mongos.*.name,
     ip_mongos = [for instance in docker_container.mongos : instance.network_data[0].ip_address],
     hostname_arbiters = docker_container.arbiter.*.name,
     ip_arbiters = [for instance in docker_container.arbiter : instance.network_data[0].ip_address],
     ssh_user = var.my_ssh_user,
     hostname_pmm = docker_container.pmm.name,
     public_ip_pmm = docker_container.pmm.network_data[0].ip_address
    }
  )
  filename = "ssh_config"
}
