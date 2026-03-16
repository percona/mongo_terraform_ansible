resource "chaos_instance" "minio" {
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
    ssh_authorized_keys:
      %{~ for user, key_path in var.chaos_ssh_users}
      - ${trimspace(file(key_path))}
      %{~ endfor}
    runcmd:
      - hostnamectl set-hostname "${local.minio_host}"
      - echo "127.0.0.1 $(hostname) localhost" > /etc/hosts
      - mkdir -p /data/minio
      - curl -fsSL https://dl.min.io/server/minio/release/linux-amd64/minio -o /usr/local/bin/minio
      - chmod +x /usr/local/bin/minio
      - curl -fsSL https://dl.min.io/client/mc/release/linux-amd64/mc -o /usr/local/bin/mc
      - chmod +x /usr/local/bin/mc
      - groupadd -r minio-user
      - useradd -M -r -g minio-user minio-user
      - chown minio-user:minio-user /data/minio
      - |
        cat > /etc/default/minio << 'EOF'
        MINIO_VOLUMES="/data/minio"
        MINIO_ROOT_USER="${var.minio_root_user}"
        MINIO_ROOT_PASSWORD="${var.minio_root_password}"
        EOF
      - |
        cat > /etc/systemd/system/minio.service << 'EOF'
        [Unit]
        Description=MinIO Object Storage Server
        After=network-online.target
        [Service]
        Type=notify
        User=minio-user
        Group=minio-user
        EnvironmentFile=/etc/default/minio
        ExecStart=/usr/local/bin/minio server $MINIO_VOLUMES --console-address ":${var.minio_console_port}"
        Restart=always
        RestartSec=5
        [Install]
        WantedBy=multi-user.target
        EOF
      - systemctl daemon-reload
      - systemctl enable minio
      - systemctl start minio
      - sleep 15
      - /usr/local/bin/mc alias set local http://127.0.0.1:${var.minio_port} "${var.minio_root_user}" "${var.minio_root_password}"
      - /usr/local/bin/mc mb local/"${local.bucket_name}" || true
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
      port     = tostring(var.minio_port)
      protocol = "tcp"
      comment  = "Allow Minio API access from subnet"
    },
    {
      source   = var.subnet_cidr
      port     = tostring(var.minio_console_port)
      protocol = "tcp"
      comment  = "Allow Minio console access from subnet"
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
