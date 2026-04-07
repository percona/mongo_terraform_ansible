resource "chaos_instance" "replset" {
  count             = var.data_nodes_per_replset
  name              = "${var.prefix}-${var.rs_name}-${var.replset_tag}${count.index}"
  os                = var.os_image
  cpu_cores         = var.replsetsvr_cpu_cores
  memory            = var.replsetsvr_memory_gb
  disk              = var.replsetsvr_volume_size
  ssh_user          = var.my_ssh_user
  description       = "${var.prefix}-${var.rs_name} – MongoDB replica set data node ${count.index}"
  delete_after_days = var.delete_after_days

  user_data = <<-CLOUDINIT
    #cloud-config
    runcmd:
      - hostnamectl set-hostname "${var.prefix}-${var.rs_name}-${var.replset_tag}${count.index}"
      - echo "127.0.0.1 $(hostname) localhost" > /etc/hosts
      - mkdir -p /var/lib/mongo
  CLOUDINIT

  firewall_rules = toset(concat(
    var.firewall_rules,
    length(var.firewall_rules) == 0 && var.source_ranges != "" ? [
      {
        source   = var.source_ranges
        port     = tostring(var.replsetsvr_port)
        protocol = "tcp"
        comment  = "Allow MongoDB access"
      },
    ] : [],
    [
      {
        source   = "10.30.0.0/16"
        port     = tostring(var.replsetsvr_port)
        protocol = "tcp"
        comment  = "Allow MongoDB access from subnet"
      },
    ]
  ))
}
