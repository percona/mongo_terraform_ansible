# MinIO Docker container
data "docker_registry_image" "minio" {
  name = var.minio_image
}

locals {
  minio_repository    = replace(data.docker_registry_image.minio.name, "/(@sha256:[a-f0-9]+|:[^/]+)$/", "")
  minio_mc_repository = replace(data.docker_registry_image.minio_mc.name, "/(@sha256:[a-f0-9]+|:[^/]+)$/", "")
}

resource "docker_image" "minio" {
  name          = "${local.minio_repository}@${data.docker_registry_image.minio.sha256_digest}"
  pull_triggers = [data.docker_registry_image.minio.sha256_digest]
  keep_locally  = true
}

# MinIO MC Command container
data "docker_registry_image" "minio_mc" {
  name = var.minio_mc_image
}
resource "docker_image" "minio_mc" {
  name          = "${local.minio_mc_repository}@${data.docker_registry_image.minio_mc.sha256_digest}"
  pull_triggers = [data.docker_registry_image.minio_mc.sha256_digest]
  keep_locally  = true
}

resource "docker_volume" "minio_data" {
  name = "${var.minio_server}-data"
}

resource "docker_container" "minio" {
  name       = var.minio_server
  hostname   = var.minio_server
  domainname = var.domain_name
  image      = docker_image.minio.image_id
  env = [
    "MINIO_ROOT_USER=${var.minio_access_key}",
    "MINIO_ROOT_PASSWORD=${var.minio_secret_key}",
    "MINIO_ADDRESS=:${var.minio_port}",
    "MINIO_CONSOLE_ADDRESS=:${var.minio_console_port}"
  ]
  command = ["server", "/data"]
  volumes {
    volume_name    = docker_volume.minio_data.name
    container_path = "/data"
  }
  ports {
    internal = var.minio_port
    external = var.minio_port
    ip       = var.bind_to_localhost ? "127.0.0.1" : "0.0.0.0"
  }
  ports {
    internal = var.minio_console_port
    external = var.minio_console_port
    ip       = var.bind_to_localhost ? "127.0.0.1" : "0.0.0.0"
  }
  network_mode = "bridge"
  networks_advanced {
    name = var.network_name
  }
  healthcheck {
    test         = ["CMD", "curl", "-k", "-f", "http://${var.minio_server}:${var.minio_port}/minio/health/live"]
    interval     = "10s"
    timeout      = "5s"
    retries      = 5
    start_period = "30s"
  }
  wait    = true
  restart = "on-failure"

  lifecycle {
    replace_triggered_by = [docker_image.minio]
  }
}

# Initialize MinIO bucket using the MinIO client (`mc`)
resource "null_resource" "minio_bucket" {
  depends_on = [docker_container.minio]

  triggers = {
    minio_data_volume_id = docker_volume.minio_data.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      if ! docker run --rm --network ${var.network_name} \
          -e MC_HOST_minio="http://${var.minio_access_key}:${var.minio_secret_key}@${docker_container.minio.name}:${var.minio_port}" \
          ${docker_image.minio_mc.image_id} stat minio/${var.bucket_name} >/dev/null 2>&1; then
        docker run --rm --network ${var.network_name} \
          -e MC_HOST_minio="http://${var.minio_access_key}:${var.minio_secret_key}@${docker_container.minio.name}:${var.minio_port}" \
          ${docker_image.minio_mc.image_id} mb minio/${var.bucket_name} --region=${var.minio_region}
        docker run --rm --network ${var.network_name} \
          -e MC_HOST_minio="http://${var.minio_access_key}:${var.minio_secret_key}@${docker_container.minio.name}:${var.minio_port}" \
          ${docker_image.minio_mc.image_id} ilm rule add --expire-days ${var.backup_retention} minio/${var.bucket_name}
      fi
    EOT
  }
}
