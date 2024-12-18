locals {
  storage_config_content = templatefile("pbm-storage.tmpl", {
    minio_region     = var.minio_region
    bucket_name      = var.bucket_name
    env_tag          = var.env_tag
    minio_server     = "${var.env_tag}-${var.minio_server}"
    minio_port      = var.minio_port
    minio_access_key = var.minio_access_key
    minio_secret_key = var.minio_secret_key  
  })
  dockerfile_content = templatefile("Dockerfile.tmpl", {
    psmdb_image      = var.psmdb_image
    pbm_image        = var.pbm_image
    base_os_image    = var.base_os_image        
  })  
}

resource "local_file" "mongodb_keyfile" {
  filename = "${path.module}/mongodb-keyfile.key"
  content  = var.keyfile
  file_permission = "0600"
}

resource "local_file" "storage_config" {
  filename = "${path.module}/pbm-storage.conf"
  content  = local.storage_config_content
}

resource "local_file" "dockerfile_content" {
  filename = "${path.module}/Dockerfile"
  content  = local.dockerfile_content
}

resource "null_resource" "docker_build" {
  provisioner "local-exec" {
    command = "docker build -t ${var.custom_image} ."
  }
}