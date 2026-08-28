locals {
  ycsb_dockerfile_content = templatefile("${path.module}/ycsb.Dockerfile.tmpl", {
    ycsb_builder_image = var.enable_ycsb ? "${local.ycsb_builder_repository}@${data.docker_registry_image.ycsb_builder[0].sha256_digest}" : ""
    ycsb_os_image      = var.enable_ycsb ? "${local.ycsb_os_repository}@${data.docker_registry_image.ycsb_os[0].sha256_digest}" : ""
  })
  ycsb_dockerfile_name    = replace(var.ycsb_image, "/", "-")
  ycsb_builder_image      = "eclipse-temurin:11-jdk-jammy"
  ycsb_builder_repository = var.enable_ycsb ? replace(data.docker_registry_image.ycsb_builder[0].name, "/(@sha256:[a-f0-9]+|:[^/]+)$/", "") : ""
  ycsb_os_repository      = var.enable_ycsb ? replace(data.docker_registry_image.ycsb_os[0].name, "/(@sha256:[a-f0-9]+|:[^/]+)$/", "") : ""
}

# Write YCSB Dockerfile to disk
resource "local_file" "ycsb_dockerfile_content" {
  count    = var.enable_ycsb ? 1 : 0
  filename = "${path.module}/${local.ycsb_dockerfile_name}.Dockerfile"
  content  = local.ycsb_dockerfile_content
}

# Get base OS image
data "docker_registry_image" "ycsb_os" {
  count = var.enable_ycsb ? 1 : 0
  name  = var.ycsb_os_image
}

data "docker_registry_image" "ycsb_builder" {
  count = var.enable_ycsb ? 1 : 0
  name  = local.ycsb_builder_image
}

resource "docker_image" "ycsb_os" {
  count         = var.enable_ycsb ? 1 : 0
  name          = "${local.ycsb_os_repository}@${data.docker_registry_image.ycsb_os[0].sha256_digest}"
  pull_triggers = [data.docker_registry_image.ycsb_os[0].sha256_digest]
  keep_locally  = true
}

resource "docker_image" "ycsb_builder" {
  count         = var.enable_ycsb ? 1 : 0
  name          = "${local.ycsb_builder_repository}@${data.docker_registry_image.ycsb_builder[0].sha256_digest}"
  pull_triggers = [data.docker_registry_image.ycsb_builder[0].sha256_digest]
  keep_locally  = true
}

# Build YCSB Docker image
resource "docker_image" "ycsb" {
  count = var.enable_ycsb ? 1 : 0
  depends_on = [
    docker_image.ycsb_os,
    docker_image.ycsb_builder,
    local_file.ycsb_dockerfile_content,
  ]
  name         = var.ycsb_image
  keep_locally = true
  triggers = {
    builder_digest = data.docker_registry_image.ycsb_builder[0].sha256_digest
    os_digest      = data.docker_registry_image.ycsb_os[0].sha256_digest
  }
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
