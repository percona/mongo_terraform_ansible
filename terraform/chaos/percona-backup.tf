resource "chaos_instance" "minio" {
  name              = local.minio_host
  os                = var.os_image
  vcpu              = var.minio_cpu_cores
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

  firewall_rules = [
    {
      source   = var.source_ranges
      port     = "22"
      protocol = "tcp"
      comment  = "Allow SSH access"
    },
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
  ]
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
  value       = "http://${chaos_instance.minio.ip_address}:${var.minio_port}"
  description = "Minio S3-compatible endpoint URL for backup configuration"
}
