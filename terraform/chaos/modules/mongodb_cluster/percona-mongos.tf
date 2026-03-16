resource "chaos_instance" "mongos" {
  count             = var.mongos_count
  name              = "${var.cluster_name}-${var.mongos_tag}0${count.index}"
  os                = var.os_image
  cpu_cores         = var.mongos_cpu_cores
  memory            = var.mongos_memory_gb
  disk              = 20
  ssh_user          = var.my_ssh_user
  description       = "${var.cluster_name} – MongoDB mongos router ${count.index}"
  delete_after_days = var.delete_after_days

  user_data = <<-CLOUDINIT
    #cloud-config
    runcmd:
      - hostnamectl set-hostname "${var.cluster_name}-${var.mongos_tag}0${count.index}"
      - echo "127.0.0.1 $(hostname) localhost" > /etc/hosts
  CLOUDINIT

  firewall_rules = [
    {
      source   = var.source_ranges
      port     = "22"
      protocol = "tcp"
      comment  = "Allow SSH access"
    },
  ]
}
