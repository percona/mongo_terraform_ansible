variable "controller_dir" { type = string }
variable "topologies" { type = map(bool) }
variable "enabled" {
  type    = bool
  default = false
}

locals {
  previous = fileexists("${var.controller_dir}/topologies.json") ? jsondecode(file("${var.controller_dir}/topologies.json")) : {}
}

resource "terraform_data" "mode" {
  input = var.topologies
  lifecycle {
    precondition {
      condition     = !var.enabled || length(var.topologies) > 0
      error_message = "Vault encryption requires at least one MongoDB topology in the environment."
    }
    precondition {
      condition     = alltrue([for name, enabled in local.previous : try(var.topologies[name] == enabled, false)])
      error_message = "Changing/removing encryption on an existing topology requires migration or recreation. Use terraform destroy with the original configuration to delete the environment."
    }
  }
}
