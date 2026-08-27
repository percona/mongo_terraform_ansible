resource "chaos_instance" "ca" {
  count             = var.enable_ca && var.ca_placement == "dedicated" ? 1 : 0
  name              = local.ca_host
  os                = var.os_image
  cpu_cores         = var.ca_cpu_cores
  memory            = var.ca_memory_gb
  disk              = var.ca_volume_size
  ssh_user          = var.my_ssh_user
  description       = "${var.prefix} - TLS certificate authority"
  delete_after_days = var.delete_after_days

  user_data = <<-CLOUDINIT
    #cloud-config
    runcmd:
      - hostnamectl set-hostname "${local.ca_host}"
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
