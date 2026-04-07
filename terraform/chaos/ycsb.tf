resource "chaos_instance" "ycsb" {
  count             = var.enable_ycsb ? 1 : 0
  name              = local.ycsb_host
  os                = var.os_image
  cpu_cores         = var.ycsb_cpu_cores
  memory            = var.ycsb_memory_gb
  disk              = var.ycsb_volume_size
  ssh_user          = var.my_ssh_user
  description       = "${var.prefix} – YCSB workload generator"
  delete_after_days = var.delete_after_days

  user_data = <<-CLOUDINIT
    #cloud-config
    runcmd:
      - hostnamectl set-hostname "${local.ycsb_host}"
      - echo "127.0.0.1 $(hostname) localhost" > /etc/hosts
  CLOUDINIT

  firewall_rules = toset(concat(
    var.firewall_rules,
    length(var.firewall_rules) == 0 && var.source_ranges != "" ? [
      {
        source   = var.source_ranges
        port     = "22"
        protocol = "tcp"
        comment  = "Allow SSH access"
      },
    ] : [],
    [
      {
        source   = "10.30.0.0/16"
        port     = "22"
        protocol = "tcp"
        comment  = "Allow SSH access from subnet"
      },
    ]
  ))
}
