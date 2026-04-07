locals {
  ycsb_dockerfile_content = templatefile("${path.module}/ycsb.Dockerfile.tmpl", {
    ycsb_os_image = var.ycsb_os_image
  })
  ycsb_dockerfile_name = replace(var.ycsb_image, "/", "-")
}

# Write YCSB Dockerfile to disk
resource "local_file" "ycsb_dockerfile_content" {
  count    = var.enable_ycsb ? 1 : 0
  filename = "${path.module}/${local.ycsb_dockerfile_name}.Dockerfile"
  content  = local.ycsb_dockerfile_content
}

# Get base OS image
data "docker_registry_image" "ycsb" {
  count = var.enable_ycsb ? 1 : 0
  name  = var.ycsb_os_image
}

resource "docker_image" "ycsb_os" {
  count         = var.enable_ycsb ? 1 : 0
  name          = var.ycsb_os_image
  pull_triggers = [data.docker_registry_image.ycsb[0].sha256_digest]
  keep_locally  = true
}

# Build YCSB Docker image
resource "docker_image" "ycsb" {
  count = var.enable_ycsb ? 1 : 0
  depends_on = [
    docker_image.ycsb_os
  ]
  name         = var.ycsb_image
  keep_locally = true
  build {
    context    = path.module
    dockerfile = "${local.ycsb_dockerfile_name}.Dockerfile"
  }
}

# Create YCSB container
resource "docker_container" "ycsb" {
  count        = var.enable_ycsb ? 1 : 0
  name         = "${local.name_prefix}${var.ycsb_container_suffix}"
  image        = docker_image.ycsb[0].image_id
  command      = ["sleep", "infinity"]
  network_mode = "bridge"
  networks_advanced {
    name = "${local.name_prefix}${var.network_name}"
  }
  healthcheck {
    test         = ["CMD-SHELL", "/ycsb/bin/ycsb --help"]
    interval     = "10s"
    timeout      = "10s"
    retries      = 5
    start_period = "30s"
  }
  wait    = false
  restart = "on-failure"

  depends_on = [docker_network.mongo_network]
}
