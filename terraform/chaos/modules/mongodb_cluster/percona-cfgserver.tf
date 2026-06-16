resource "chaos_instance" "cfg" {
  for_each          = local.cfg_members
  name              = "${var.prefix}-${var.cluster_name}-${var.configsvr_tag}0${each.value}"
  os                = var.os_image
  cpu_cores         = var.configsvr_cpu_cores
  memory            = var.configsvr_memory_gb
  disk              = var.configsvr_volume_size
  ssh_user          = var.my_ssh_user
  description       = "${var.prefix}-${var.cluster_name} – MongoDB config server ${each.value}"
  delete_after_days = var.delete_after_days

  user_data = <<-CLOUDINIT
    #cloud-config
    runcmd:
      - hostnamectl set-hostname "${var.prefix}-${var.cluster_name}-${var.configsvr_tag}0${each.value}"
      - echo "127.0.0.1 $(hostname) localhost" > /etc/hosts
      - mkdir -p /var/lib/mongo
  CLOUDINIT

  firewall_rules = toset(concat(
    var.firewall_rules,
    length(var.firewall_rules) == 0 && var.source_ranges != "" ? [
      {
        source   = var.source_ranges
        port     = tostring(var.configsvr_port)
        protocol = "tcp"
        comment  = "Allow MongoDB config server access"
      },
    ] : [],
    [
      {
        source   = "10.30.0.0/16"
        port     = tostring(var.configsvr_port)
        protocol = "tcp"
        comment  = "Allow MongoDB access from subnet"
      },
    ]
  ))
}
