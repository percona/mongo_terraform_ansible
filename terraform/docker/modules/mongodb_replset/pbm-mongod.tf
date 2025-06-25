# Prepare the template for PBM docker image with the MongoDB binary of the version in use (required for physical restore)
locals {
  pbm_mongod_image_dockerfile_content = templatefile("${path.module}/pbm-mongod.Dockerfile.tmpl", {
    psmdb_image      = var.psmdb_image
    pbm_image        = var.pbm_image
    base_os_image    = var.base_os_image        
  })  
}

resource "docker_image" "psmdb" {
  name         = var.psmdb_image
  keep_locally = true
}

resource "docker_image" "pbm" {
  name         = var.pbm_image
  keep_locally = true
}

resource "docker_image" "base_os" {
  name         = var.base_os_image
  keep_locally = true
}

# Write PBM Dockerfile to disk
resource "local_file" "pbm_mongod_image_dockerfile_content" {
  filename = "${path.module}/${var.rs_name}-${var.pbm_mongod_image}.Dockerfile"
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
  name = var.pbm_mongod_image
  build {
    context    = path.module
    dockerfile = "${var.rs_name}-${var.pbm_mongod_image}.Dockerfile"
  }
}