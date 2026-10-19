resource "chaos_instance" "pmm_bare_client" {
  for_each          = var.pmm_bare_clients
  name              = "${var.prefix}-${each.key}"
  os                = coalesce(each.value.os_image, var.os_image)
  cpu_cores         = each.value.cpu_cores
  memory            = each.value.memory_gb
  disk              = each.value.volume_size
  ssh_user          = var.my_ssh_user
  description       = "${var.prefix} - PMM client without MongoDB"
  delete_after_days = var.delete_after_days

  user_data = <<-CLOUDINIT
    #cloud-config
    runcmd:
      - hostnamectl set-hostname "${var.prefix}-${each.key}"
      - echo "127.0.0.1 $(hostname) localhost" > /etc/hosts
  CLOUDINIT

  # MongoDB's port is open so that PMM Extensions can bootstrap a replica set across these hosts.
  firewall_rules = toset(concat(
    var.firewall_rules,
    length(var.firewall_rules) == 0 && var.source_ranges != "" ? [
      {
        source   = var.source_ranges
        port     = "27017"
        protocol = "tcp"
        comment  = "Allow MongoDB access"
      },
    ] : [],
    [
      {
        source   = "10.30.0.0/16"
        port     = "27017"
        protocol = "tcp"
        comment  = "Allow MongoDB access from subnet"
      },
    ]
  ))
}
