resource "chaos_instance" "arbiter" {
  count             = var.arbiters_per_replset
  name              = "${var.rs_name}-${var.arbiter_tag}${count.index}"
  os                = var.os_image
  cpu_cores         = var.arbiter_cpu_cores
  memory            = var.arbiter_memory_gb
  disk              = 10
  ssh_user          = var.my_ssh_user
  description       = "${var.rs_name} – MongoDB arbiter ${count.index}"
  delete_after_days = var.delete_after_days

  user_data = <<-CLOUDINIT
    #cloud-config
    ssh_authorized_keys:
      %{~ for user, key_path in var.chaos_ssh_users}
      - ${trimspace(file(key_path))}
      %{~ endfor}
    runcmd:
      - hostnamectl set-hostname "${var.rs_name}-${var.arbiter_tag}${count.index}"
      - echo "127.0.0.1 $(hostname) localhost" > /etc/hosts
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
      port     = tostring(var.arbiter_port)
      protocol = "tcp"
      comment  = "Allow MongoDB arbiter port from subnet"
    },
  ]
}
