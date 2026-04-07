# Prepare the temporary container to initialize the keyfile volume
resource "docker_volume" "keyfile_volume" {
  name = "${var.rs_name}-shared_keyfile"
}

resource "null_resource" "init_keyfile" {
  triggers = {
    volume_name           = docker_volume.keyfile_volume.name
    base_os_image_id      = docker_image.base_os.image_id
    keyfile_name          = var.keyfile_name
    keyfile_contents_hash = sha256(var.keyfile_contents)
    keyfile_owner_uid     = tostring(var.uid)
  }

  provisioner "local-exec" {
    command = <<-EOT
      docker run --rm \
        -e KEYFILE_CONTENTS \
        -v ${docker_volume.keyfile_volume.name}:/mnt \
        ${docker_image.base_os.image_id} \
        sh -c 'printf "%s" "$KEYFILE_CONTENTS" > /mnt/${var.keyfile_name} && chmod 600 /mnt/${var.keyfile_name} && chown ${var.uid} /mnt/${var.keyfile_name}'
    EOT

    environment = {
      KEYFILE_CONTENTS = var.keyfile_contents
    }
  }
}
