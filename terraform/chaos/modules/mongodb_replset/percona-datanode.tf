resource "chaos_instance" "replset" {
  count             = var.data_nodes_per_replset
  name              = "${var.rs_name}-${var.replset_tag}${count.index}"
  os                = var.os_image
  cpu_cores         = var.replsetsvr_cpu_cores
  memory            = var.replsetsvr_memory_gb
  disk              = var.replsetsvr_volume_size
  ssh_user          = var.my_ssh_user
  description       = "${var.rs_name} – MongoDB replica set data node ${count.index}"
  delete_after_days = var.delete_after_days

  user_data = <<-CLOUDINIT
    #cloud-config
    runcmd:
      - hostnamectl set-hostname "${var.rs_name}-${var.replset_tag}${count.index}"
      - echo "127.0.0.1 $(hostname) localhost" > /etc/hosts
      - mkdir -p /var/lib/mongo
  CLOUDINIT

  firewall_rules = concat(
    var.source_ranges != "" ? [
      {
        source   = var.source_ranges
        port     = "22"
        protocol = "tcp"
        comment  = "Allow SSH access"
      },
    ] : [],
    [
      {
        source   = var.subnet_cidr
        port     = tostring(var.replsetsvr_port)
        protocol = "tcp"
        comment  = "Allow MongoDB access from subnet"
      },
    ]
  )
}
