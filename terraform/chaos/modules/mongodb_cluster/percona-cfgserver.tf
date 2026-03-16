resource "chaos_instance" "cfg" {
  count             = var.configsvr_count
  name              = "${var.cluster_name}-${var.configsvr_tag}0${count.index}"
  os                = var.os_image
  cpu_cores         = var.configsvr_cpu_cores
  memory            = var.configsvr_memory_gb
  disk              = var.configsvr_volume_size
  ssh_user          = var.my_ssh_user
  description       = "${var.cluster_name} – MongoDB config server ${count.index}"
  delete_after_days = var.delete_after_days

  user_data = <<-CLOUDINIT
    #cloud-config
    ssh_authorized_keys:
      %{~ for user, key_path in var.chaos_ssh_users}
      - ${trimspace(file(key_path))}
      %{~ endfor}
    runcmd:
      - hostnamectl set-hostname "${var.cluster_name}-${var.configsvr_tag}0${count.index}"
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
      port     = tostring(var.configsvr_port)
      protocol = "tcp"
      comment  = "Allow MongoDB config server port from subnet"
    },
  ]
}
