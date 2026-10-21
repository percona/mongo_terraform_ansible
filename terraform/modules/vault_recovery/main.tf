variable "controller_dir" { type = string }

resource "terraform_data" "recovery" {
  input = {
    controller_dir = abspath(var.controller_dir)
    script         = abspath("${path.module}/../../../scripts/vault-docker.py")
  }
  provisioner "local-exec" {
    when    = destroy
    command = "python3 \"${self.input.script}\" destroy"
    environment = {
      VAULT_CONTROLLER_DIR = self.input.controller_dir
    }
  }
}
