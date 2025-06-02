resource "docker_image" "psmdb" {
  name         = var.psmdb_image
  keep_locally = true
}

resource "docker_image" "pbm" {
  name         = var.pbm_image
  keep_locally = true
}

resource "docker_image" "pmm_client" {
  name         = var.pmm_client_image
  keep_locally = true
}

resource "docker_image" "base_os" {
  name         = var.base_os_image
  keep_locally = true
}

resource "docker_image" "pbm_mongod" {
  name         = var.pbm_mongod_image
  keep_locally = true
}

# Prepare the temporary container to initialize the keyfile volume
resource "docker_volume" "keyfile_volume" {
  name = "shared_keyfile"
}

resource "docker_container" "init_keyfile" {
  name  = "${var.cluster_name}-init_keyfile_container"
  image = docker_image.base_os.image_id
  network_mode = "bridge"
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
  #rm = true
}
