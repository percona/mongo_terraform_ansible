# Prepare the template for PBM docker image with the MongoDB binary of the version in use (required for physical restore)
locals {
  psmdb_repository   = replace(data.docker_registry_image.psmdb.name, "/(@sha256:[a-f0-9]+|:[^/]+)$/", "")
  pbm_repository     = replace(data.docker_registry_image.pbm.name, "/(@sha256:[a-f0-9]+|:[^/]+)$/", "")
  base_os_repository = replace(data.docker_registry_image.base_os.name, "/(@sha256:[a-f0-9]+|:[^/]+)$/", "")
  mongot_repository  = replace(data.docker_registry_image.mongot.name, "/(@sha256:[a-f0-9]+|:[^/]+)$/", "")

  pbm_mongod_image_dockerfile_content = templatefile("${path.module}/pbm-mongod.Dockerfile.tmpl", {
    psmdb_image   = "${local.psmdb_repository}@${data.docker_registry_image.psmdb.sha256_digest}"
    pbm_image     = "${local.pbm_repository}@${data.docker_registry_image.pbm.sha256_digest}"
    base_os_image = "${local.base_os_repository}@${data.docker_registry_image.base_os.sha256_digest}"
  })
}

data "docker_registry_image" "psmdb" {
  name = var.psmdb_image
}

resource "docker_image" "psmdb" {
  name          = "${local.psmdb_repository}@${data.docker_registry_image.psmdb.sha256_digest}"
  pull_triggers = [data.docker_registry_image.psmdb.sha256_digest]
  keep_locally  = true
}

data "docker_registry_image" "pbm" {
  name = var.pbm_image
}

resource "docker_image" "pbm" {
  name          = "${local.pbm_repository}@${data.docker_registry_image.pbm.sha256_digest}"
  pull_triggers = [data.docker_registry_image.pbm.sha256_digest]
  keep_locally  = true
}

data "docker_registry_image" "base_os" {
  name = var.base_os_image
}

resource "docker_image" "base_os" {
  name          = "${local.base_os_repository}@${data.docker_registry_image.base_os.sha256_digest}"
  pull_triggers = [data.docker_registry_image.base_os.sha256_digest]
  keep_locally  = true
}

data "docker_registry_image" "mongot" {
  name = var.mongot_image
}

resource "docker_image" "mongot" {
  name          = "${local.mongot_repository}@${data.docker_registry_image.mongot.sha256_digest}"
  pull_triggers = [data.docker_registry_image.mongot.sha256_digest]
  keep_locally  = true
}

# Write PBM Dockerfile to disk
resource "local_file" "pbm_mongod_image_dockerfile_content" {
  filename = "${path.module}/${var.cluster_name}-${replace(var.pbm_mongod_image, "/", "-")}.Dockerfile"
  content  = local.pbm_mongod_image_dockerfile_content
}

# Build PBM custom Docker image 
resource "docker_image" "pbm_mongod" {
  depends_on = [
    local_file.pbm_mongod_image_dockerfile_content,
    docker_image.psmdb,
    docker_image.pbm,
    docker_image.base_os
  ]
  name = "${var.cluster_name}-${var.pbm_mongod_image}"
  triggers = {
    psmdb_digest   = data.docker_registry_image.psmdb.sha256_digest
    pbm_digest     = data.docker_registry_image.pbm.sha256_digest
    base_os_digest = data.docker_registry_image.base_os.sha256_digest
  }
  build {
    context    = path.module
    dockerfile = "${var.cluster_name}-${replace(var.pbm_mongod_image, "/", "-")}.Dockerfile"
  }
}
