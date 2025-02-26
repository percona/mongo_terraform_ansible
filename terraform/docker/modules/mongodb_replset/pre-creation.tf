locals {
  storage_config_content = templatefile("${path.module}/pbm-storage.tmpl", {
    minio_region     = var.minio_region
    bucket_name      = var.bucket_name
    rs_name          = var.rs_name
    minio_server     = var.minio_server
    minio_port       = var.minio_port
    minio_access_key = var.minio_access_key
    minio_secret_key = var.minio_secret_key  
  })
  custom_image_dockerfile_content = templatefile("${path.module}/custom_image.Dockerfile.tmpl", {
    psmdb_image      = var.psmdb_image
    pbm_image        = var.pbm_image
    base_os_image    = var.base_os_image        
  })  
  ycsb_dockerfile_content = templatefile("${path.module}/ycsb.Dockerfile.tmpl", {
    ycsb_os_image    = var.ycsb_os_image        
  })    
}

resource "docker_volume" "keyfile_volume" {
  name = "shared_keyfile"
}

resource "docker_container" "init_keyfile_container" {
  name  = "init_keyfile_container"
  image = var.base_os_image
  command = [
    "sh",
    "-c",
    "echo '${var.keyfile_contents}' > /mnt/${var.keyfile_name} && chmod 600 /mnt/${var.keyfile_name} && chown ${var.uid} /mnt/${var.keyfile_name}"
  ]
  mounts {
    target = "/mnt"
    source = docker_volume.keyfile_volume.name
    type   = "volume"
  }
  user = "root"
  must_run = false
}

resource "null_resource" "remove_init_keyfile_container" {
  depends_on = [docker_container.init_keyfile_container]
  provisioner "local-exec" {
    command = "docker rm -f init_keyfile_container"
  }
}

resource "local_file" "storage_config" {
  filename = "${path.module}/pbm-storage.conf.${var.rs_name}"
  content  = local.storage_config_content
}

resource "local_file" "custom_image_dockerfile_content" {
  filename = "${path.module}/${var.custom_image}.Dockerfile"
  content  = local.custom_image_dockerfile_content
}

resource "null_resource" "docker_build_custom_image" {
  provisioner "local-exec" {
    command = "docker build -t ${var.custom_image} -f ${path.module}/${var.custom_image}.Dockerfile ."
  }
}

resource "local_file" "ycsdb_dockerfile_content" {
  filename = "${path.module}/${var.ycsb_image}.Dockerfile"
  content  = local.ycsb_dockerfile_content
}

resource "null_resource" "docker_build_ycsb" {
  provisioner "local-exec" {
    command = "docker build -t ${var.ycsb_image} -f ${path.module}/${var.ycsb_image}.Dockerfile ."
  }
}