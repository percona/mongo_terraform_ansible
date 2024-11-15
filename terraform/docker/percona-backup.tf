# MinIO Docker container
resource "docker_container" "minio" {
  name  = var.minio_server
  image = var.minio_image
  env = [
    "MINIO_ROOT_USER=${var.minio_access_key}",
    "MINIO_ROOT_PASSWORD=${var.minio_secret_key}",
  ]
  command = ["server", "/data"]
  ports {
    internal = var.minio_port
    external = 19000
  }
  networks_advanced {
    name = docker_network.mongo_network.id
  }
}

# Initialize MinIO bucket using the MinIO client (`mc`)
resource "null_resource" "minio_bucket" {
  depends_on = [docker_container.minio]

  provisioner "local-exec" {
    command = <<-EOT
      docker run --rm --network ${docker_network.mongo_network.name} \
        -e MC_HOST_minio="http://${var.minio_access_key}:${var.minio_secret_key}@${docker_container.minio.name}:${var.minio_port}" \
        minio/mc mb minio/${var.bucket_name} --region=${var.minio_region}
    EOT
  }
}

# PBM container
resource "docker_container" "pbm_cli" {
  name  = "${var.env_tag}-mongodb-pbm-cli"
  count = 1
  image = var.pbm_image 
  command = ["/bin/sh", "-c", "while true; do sleep 86400; done;"]
  env = [ "PBM_MONGODB_URI=pbm:percona@${docker_container.cfg[0].name}:27019" ]
  networks_advanced {
    name = docker_network.mongo_network.id
  }
  healthcheck {
    test        = ["CMD-SHELL", "pbm version"]
    interval    = "10s"
    timeout     = "2s"
    retries     = 5
    start_period = "30s"
  }   
  wait = true     
  restart = "on-failure"
}
