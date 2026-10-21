variable "vault_encryption" {
  type    = bool
  default = false
}
variable "vault_server" {
  type    = string
  default = ""
}
variable "vault_topology" {
  type    = string
  default = ""
}
variable "vault_credentials" {
  type    = string
  default = ""
}

resource "terraform_data" "vault_data_mode" {
  for_each         = var.vault_encryption ? merge(docker_volume.shard_volume, docker_volume.cfg_volume) : {}
  triggers_replace = [var.vault_encryption, each.value.id]
  provisioner "local-exec" {
    command = "python3 \"${abspath(path.module)}/../../../../scripts/vault-docker.py\" check-data"
    environment = {
      VAULT_DATA_VOLUME = each.value.name
      VAULT_ENCRYPTION  = tostring(var.vault_encryption)
      VAULT_IMAGE       = docker_image.psmdb.image_id
      MONGO_UID         = tostring(var.uid)
    }
  }
}
