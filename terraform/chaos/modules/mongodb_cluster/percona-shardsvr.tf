locals {
  shard_members = {
    for member in flatten([
      for shard_index in range(var.shard_count) : [
        for replica_index in range(var.shardsvr_replicas) : {
          key           = "shard${shard_index}svr${replica_index}"
          shard_index   = shard_index
          replica_index = replica_index
        }
      ]
    ]) : member.key => member
  }

  shard_member_keys = flatten([
    for shard_index in range(var.shard_count) : [
      for replica_index in range(var.shardsvr_replicas) : "shard${shard_index}svr${replica_index}"
    ]
  ])

  cfg_members        = { for cfg_index in range(var.configsvr_count) : "cfg${cfg_index}" => cfg_index }
  cfg_member_keys    = [for cfg_index in range(var.configsvr_count) : "cfg${cfg_index}"]
  mongos_members     = { for mongos_index in range(var.mongos_count) : "mongos${mongos_index}" => mongos_index }
  mongos_member_keys = [for mongos_index in range(var.mongos_count) : "mongos${mongos_index}"]

  arbiter_members = {
    for member in flatten([
      for shard_index in range(var.shard_count) : [
        for arbiter_index in range(var.arbiters_per_replset) : {
          key           = "shard${shard_index}arb${arbiter_index}"
          shard_index   = shard_index
          arbiter_index = arbiter_index
        }
      ]
    ]) : member.key => member
  }

  arbiter_member_keys = flatten([
    for shard_index in range(var.shard_count) : [
      for arbiter_index in range(var.arbiters_per_replset) : "shard${shard_index}arb${arbiter_index}"
    ]
  ])
}

resource "chaos_instance" "shard" {
  for_each          = local.shard_members
  name              = "${var.prefix}-${var.cluster_name}-${var.shardsvr_tag}0${each.value.shard_index}svr${each.value.replica_index}"
  os                = var.os_image
  cpu_cores         = var.shardsvr_cpu_cores
  memory            = var.shardsvr_memory_gb
  disk              = var.shardsvr_volume_size
  ssh_user          = var.my_ssh_user
  description       = "${var.prefix}-${var.cluster_name} – MongoDB shard0${each.value.shard_index} data node ${each.value.replica_index}"
  delete_after_days = var.delete_after_days

  user_data = <<-CLOUDINIT
    #cloud-config
    runcmd:
      - hostnamectl set-hostname "${var.prefix}-${var.cluster_name}-${var.shardsvr_tag}0${each.value.shard_index}svr${each.value.replica_index}"
      - echo "127.0.0.1 $(hostname) localhost" > /etc/hosts
      - mkdir -p /var/lib/mongo
  CLOUDINIT

  firewall_rules = toset(concat(
    var.firewall_rules,
    length(var.firewall_rules) == 0 && var.source_ranges != "" ? [
      {
        source   = var.source_ranges
        port     = tostring(var.shard_port)
        protocol = "tcp"
        comment  = "Allow MongoDB access"
      },
    ] : [],
    [
      {
        source   = "10.30.0.0/16"
        port     = tostring(var.shard_port)
        protocol = "tcp"
        comment  = "Allow MongoDB access from subnet"
      },
    ]
  ))
}
