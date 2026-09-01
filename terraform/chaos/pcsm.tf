resource "chaos_instance" "pcsm" {
  count             = var.enable_pcsm ? 1 : 0
  name              = local.pcsm_host
  os                = var.os_image
  cpu_cores         = var.pcsm_cpu_cores
  memory            = var.pcsm_memory_gb
  disk              = var.pcsm_volume_size
  ssh_user          = var.my_ssh_user
  description       = "${var.prefix} - Percona ClusterSync"
  delete_after_days = var.delete_after_days

  user_data = <<-CLOUDINIT
    #cloud-config
    runcmd:
      - hostnamectl set-hostname "${local.pcsm_host}"
  CLOUDINIT

  firewall_rules = toset(concat(
    length(var.firewall_rules) == 0 && var.source_ranges != "" ? [
      {
        source   = var.source_ranges
        port     = "22"
        protocol = "tcp"
        comment  = "Allow SSH access"
      },
    ] : [for rule in var.firewall_rules : rule if rule.port == "22"],
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
