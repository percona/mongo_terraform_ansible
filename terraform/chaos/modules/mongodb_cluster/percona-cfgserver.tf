resource "chaos_instance" "cfg" {
  count             = var.configsvr_count
  name              = "${var.cluster_name}-${var.configsvr_tag}0${count.index}"
  os                = var.os_image
  vcpu              = var.configsvr_cpu_cores
  memory            = var.configsvr_memory_gb
  disk              = var.configsvr_volume_size
  ssh_user          = var.my_ssh_user
  description       = "${var.cluster_name} – MongoDB config server ${count.index}"
  delete_after_days = var.delete_after_days

  user_data = <<-CLOUDINIT
    #cloud-config
    runcmd:
      - hostnamectl set-hostname "${var.cluster_name}-${var.configsvr_tag}0${count.index}"
      - echo "127.0.0.1 $(hostname) localhost" > /etc/hosts
      - mkdir -p /var/lib/mongo
  CLOUDINIT

  firewall_rules = var.source_ranges != "" ? [
    {
      source   = var.source_ranges
      port     = "22"
      protocol = "tcp"
      comment  = "Allow SSH access"
    },
  ] : []
}
