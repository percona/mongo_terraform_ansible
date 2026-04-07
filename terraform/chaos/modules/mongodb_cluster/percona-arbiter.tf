resource "chaos_instance" "arbiter" {
  count             = var.shard_count * var.arbiters_per_replset
  name              = "${var.prefix}-${var.cluster_name}-${var.shardsvr_tag}0${floor(count.index / var.arbiters_per_replset)}arb${count.index % var.arbiters_per_replset}"
  os                = var.os_image
  cpu_cores         = var.arbiter_cpu_cores
  memory            = var.arbiter_memory_gb
  disk              = 20
  ssh_user          = var.my_ssh_user
  description       = "${var.prefix}-${var.cluster_name} – MongoDB shard0${floor(count.index / var.arbiters_per_replset)} arbiter ${count.index % var.arbiters_per_replset}"
  delete_after_days = var.delete_after_days

  user_data = <<-CLOUDINIT
    #cloud-config
    runcmd:
      - hostnamectl set-hostname "${var.prefix}-${var.cluster_name}-${var.shardsvr_tag}0${floor(count.index / var.arbiters_per_replset)}arb${count.index % var.arbiters_per_replset}"
      - echo "127.0.0.1 $(hostname) localhost" > /etc/hosts
  CLOUDINIT

  firewall_rules = toset(concat(
    var.firewall_rules,
    length(var.firewall_rules) == 0 && var.source_ranges != "" ? [
      {
        source   = var.source_ranges
        port     = tostring(var.arbiter_port)
        protocol = "tcp"
        comment  = "Allow MongoDB arbiter access"
      },
    ] : [],
    [
      {
        source   = "10.30.0.0/16"
        port     = tostring(var.arbiter_port)
        protocol = "tcp"
        comment  = "Allow MongoDB access from subnet"
      },
    ]
  ))
}
