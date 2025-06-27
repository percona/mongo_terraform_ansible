# MinIO Docker container
resource "docker_image" "minio" {
  name         = var.minio_image
  keep_locally = true  
}

resource "docker_container" "minio" {
  name  = var.minio_server
  hostname = var.minio_server
  domainname = var.domain_name
  image = docker_image.minio.image_id
  env = [
    "MINIO_ROOT_USER=${var.minio_access_key}",
    "MINIO_ROOT_PASSWORD=${var.minio_secret_key}",
    "MINIO_ADDRESS=:${var.minio_port}",
    "MINIO_CONSOLE_ADDRESS=:${var.minio_console_port}"
  ]
  command = ["server", "/data"]
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
    test        = [ "CMD", "curl", "-k", "-f", "http://${var.minio_server}:${var.minio_port}/minio/health/live" ]
    interval    = "10s"
    timeout     = "5s"
    retries     = 5
    start_period = "30s"
  }   
  wait = true       
  restart = "on-failure"
}

# Initialize MinIO bucket using the MinIO client (`mc`)
resource "null_resource" "minio_bucket" {
  depends_on = [docker_container.minio]

  provisioner "local-exec" {
    command = <<-EOT
      docker run --rm --network ${var.network_name} \
        -e MC_HOST_minio="http://${var.minio_access_key}:${var.minio_secret_key}@${docker_container.minio.name}:${var.minio_port}" \
        minio/mc mb minio/${var.bucket_name} --region=${var.minio_region}
    EOT
  }

  provisioner "local-exec" {
    command = <<-EOT
      docker run --rm --network ${var.network_name} \
        -e MC_HOST_minio="http://${var.minio_access_key}:${var.minio_secret_key}@${docker_container.minio.name}:${var.minio_port}" \
        minio/mc ilm rule add --expire-days ${var.backup_retention} minio/${var.bucket_name} 
    EOT
  }  
}

