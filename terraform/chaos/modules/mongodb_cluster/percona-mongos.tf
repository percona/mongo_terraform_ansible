resource "chaos_instance" "mongos" {
  count             = var.mongos_count
  name              = "${var.prefix}-${var.cluster_name}-${var.mongos_tag}0${count.index}"
  os                = var.os_image
  cpu_cores         = var.mongos_cpu_cores
  memory            = var.mongos_memory_gb
  disk              = 20
  ssh_user          = var.my_ssh_user
  description       = "${var.prefix}-${var.cluster_name} – MongoDB mongos router ${count.index}"
  delete_after_days = var.delete_after_days

  user_data = <<-CLOUDINIT
    #cloud-config
    runcmd:
      - hostnamectl set-hostname "${var.prefix}-${var.cluster_name}-${var.mongos_tag}0${count.index}"
      - echo "127.0.0.1 $(hostname) localhost" > /etc/hosts
  CLOUDINIT

  firewall_rules = concat(
    var.firewall_rules,
    length(var.firewall_rules) == 0 && var.source_ranges != "" ? [
      {
        source   = var.source_ranges
        port     = tostring(var.mongos_port)
        protocol = "tcp"
        comment  = "Allow MongoDB router access"
      },
    ] : [],
    [
      {
        source   = "10.30.50.0/24"
        port     = tostring(var.mongos_port)
        protocol = "tcp"
        comment  = "Allow MongoDB access from subnet"
      },
    ]
  )
}
