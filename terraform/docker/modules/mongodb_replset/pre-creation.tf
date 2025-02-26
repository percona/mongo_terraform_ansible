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
}

resource "docker_volume" "keyfile_volume" {
  name = "shared_keyfile"
}

resource "docker_container" "init_keyfile_container" {
  name  = "${var.rs_name}-init_keyfile_container"
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
    command = "docker rm -f ${docker_container.init_keyfile_container.name}"
  }
}

resource "local_file" "storage_config" {
  filename = "${path.module}/pbm-storage.conf.${var.rs_name}"
  content  = local.storage_config_content
}