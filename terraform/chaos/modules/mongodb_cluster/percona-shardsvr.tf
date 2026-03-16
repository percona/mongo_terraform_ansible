resource "chaos_instance" "shard" {
  count             = var.shard_count * var.shardsvr_replicas
  name              = "${var.cluster_name}-${var.shardsvr_tag}0${floor(count.index / var.shardsvr_replicas)}svr${count.index % var.shardsvr_replicas}"
  os                = var.os_image
  cpu_cores         = var.shardsvr_cpu_cores
  memory            = var.shardsvr_memory_gb
  disk              = var.shardsvr_volume_size
  ssh_user          = var.my_ssh_user
  description       = "${var.cluster_name} – MongoDB shard0${floor(count.index / var.shardsvr_replicas)} data node ${count.index % var.shardsvr_replicas}"
  delete_after_days = var.delete_after_days

  user_data = <<-CLOUDINIT
    #cloud-config
    ssh_authorized_keys:
      %{~ for user, key_path in var.chaos_ssh_users}
      - ${trimspace(file(key_path))}
      %{~ endfor}
    runcmd:
      - hostnamectl set-hostname "${var.cluster_name}-${var.shardsvr_tag}0${floor(count.index / var.shardsvr_replicas)}svr${count.index % var.shardsvr_replicas}"
      - echo "127.0.0.1 $(hostname) localhost" > /etc/hosts
      - mkdir -p /var/lib/mongo
  CLOUDINIT

  firewall_rules = [
    {
      source   = var.subnet_cidr
      port     = "0-65535"
      protocol = "tcp"
      comment  = "Allow all internal TCP traffic from subnet"
    },
    {
      source   = var.source_ranges
      port     = "22"
      protocol = "tcp"
      comment  = "Allow SSH access"
    },
    {
      source   = var.subnet_cidr
      port     = tostring(var.shard_port)
      protocol = "tcp"
      comment  = "Allow MongoDB shard port from subnet"
    },
  ]
}
