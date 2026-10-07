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
  for_each         = var.vault_encryption ? local.replset_members : {}
  triggers_replace = [var.vault_encryption, docker_volume.rs_volume[each.key].id]
  provisioner "local-exec" {
    command = "python3 \"${abspath(path.module)}/../../../../scripts/vault-docker.py\" check-data"
    environment = {
      VAULT_DATA_VOLUME = docker_volume.rs_volume[each.key].name
      VAULT_ENCRYPTION  = tostring(var.vault_encryption)
      VAULT_IMAGE       = docker_image.psmdb.image_id
      MONGO_UID         = tostring(var.uid)
    }
  }
}
