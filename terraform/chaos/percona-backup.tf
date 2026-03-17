resource "chaos_instance" "minio" {
  count             = var.enable_minio ? 1 : 0
  name              = local.minio_host
  os                = var.os_image
  cpu_cores         = var.minio_cpu_cores
  memory            = var.minio_memory_gb
  disk              = var.minio_volume_size
  ssh_user          = var.my_ssh_user
  description       = "${var.prefix} – Minio S3-compatible backup storage"
  delete_after_days = var.delete_after_days

  user_data = <<-CLOUDINIT
    #cloud-config
    runcmd:
      - hostnamectl set-hostname "${local.minio_host}"
      - echo "127.0.0.1 $(hostname) localhost" > /etc/hosts
      - mkdir -p /data/minio
  CLOUDINIT

  firewall_rules = concat(
    var.firewall_rules,
    length(var.firewall_rules) == 0 && var.source_ranges != "" ? [
      {
        source   = var.source_ranges
        port     = tostring(var.minio_port)
        protocol = "tcp"
        comment  = "Allow Minio API access"
      },
      {
        source   = var.source_ranges
        port     = tostring(var.minio_console_port)
        protocol = "tcp"
        comment  = "Allow Minio console access"
      },
    ] : [],
    [
      {
        source   = "10.30.50.0/24"
        port     = tostring(var.minio_port)
        protocol = "tcp"
        comment  = "Allow Minio API access from subnet"
      },
      {
        source   = "10.30.50.0/24"
        port     = tostring(var.minio_console_port)
        protocol = "tcp"
        comment  = "Allow Minio console access from subnet"
      },
    ]
  )
}

output "minio_access_key" {
  value       = var.minio_root_user
  description = "Minio access key (root user) for backup configuration"
}

output "minio_secret_key" {
  value       = var.minio_root_password
  sensitive   = true
  description = "Minio secret key (root password) for backup configuration"
}

output "minio_endpoint" {
  value       = var.enable_minio ? "http://${chaos_instance.minio[0].ip_address}:${var.minio_port}" : ""
  description = "Minio S3-compatible endpoint URL for backup configuration"
}
