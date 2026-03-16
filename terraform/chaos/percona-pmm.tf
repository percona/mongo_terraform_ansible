resource "chaos_instance" "pmm" {
  count             = var.enable_pmm ? 1 : 0
  name              = local.pmm_host
  os                = var.os_image
  cpu_cores         = var.pmm_cpu_cores
  memory            = var.pmm_memory_gb
  disk              = var.pmm_volume_size
  ssh_user          = var.my_ssh_user
  description       = "${var.prefix} – Percona Monitoring and Management server"
  delete_after_days = var.delete_after_days

  user_data = <<-CLOUDINIT
    #cloud-config
    ssh_authorized_keys:
      %{~ for user, key_path in var.chaos_ssh_users}
      - ${trimspace(file(key_path))}
      %{~ endfor}
    runcmd:
      - hostnamectl set-hostname "${local.pmm_host}"
      - echo "127.0.0.1 $(hostname) localhost" > /etc/hosts
      - mkdir -p /var/lib/docker
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
      source   = var.source_ranges
      port     = tostring(var.pmm_port)
      protocol = "tcp"
      comment  = "Allow PMM UI access"
    },
  ]
}
