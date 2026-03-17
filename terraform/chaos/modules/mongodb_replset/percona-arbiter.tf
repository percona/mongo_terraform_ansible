resource "chaos_instance" "arbiter" {
  count             = var.arbiters_per_replset
  name              = "${var.rs_name}-${var.arbiter_tag}${count.index}"
  os                = var.os_image
  cpu_cores         = var.arbiter_cpu_cores
  memory            = var.arbiter_memory_gb
  disk              = 20
  ssh_user          = var.my_ssh_user
  description       = "${var.rs_name} – MongoDB arbiter ${count.index}"
  delete_after_days = var.delete_after_days

  user_data = <<-CLOUDINIT
    #cloud-config
    runcmd:
      - hostnamectl set-hostname "${var.rs_name}-${var.arbiter_tag}${count.index}"
      - echo "127.0.0.1 $(hostname) localhost" > /etc/hosts
  CLOUDINIT

  firewall_rules = [
    {
      source   = "10.30.50.0/24"
      port     = tostring(var.arbiter_port)
      protocol = "tcp"
      comment  = "Allow MongoDB access from subnet"
    },
  ]
}
