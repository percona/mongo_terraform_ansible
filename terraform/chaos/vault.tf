variable "vault_cpu_cores" {
  type    = number
  default = 2
}

variable "vault_memory_gb" {
  type    = number
  default = 4
}

variable "vault_volume_size" {
  type    = number
  default = 20
}

variable "vault_controller_dir" {
  type    = string
  default = ""
}

module "vault_mode_guard" {
  source         = "../modules/vault_mode_guard"
  controller_dir = var.vault_controller_dir != "" ? abspath(var.vault_controller_dir) : abspath("${path.module}/../../ansible/.vault/chaos/${var.prefix}")
  topologies     = merge({ for n in keys(var.clusters) : "cluster-${n}" => var.vault_encryption }, { for n in keys(var.replsets) : "replset-${n}" => var.vault_encryption })
  enabled        = var.vault_encryption
}

module "vault_recovery" {
  count          = local.vault_enabled ? 1 : 0
  source         = "../modules/vault_recovery"
  controller_dir = var.vault_controller_dir != "" ? var.vault_controller_dir : "${path.module}/../../ansible/.vault/chaos/${var.prefix}"
}

locals {
  vault_host    = "${var.prefix}-vault"
  vault_enabled = var.vault_encryption && length(var.clusters) + length(var.replsets) > 0
  vault_topologies = local.vault_enabled ? concat(
    [for name in keys(var.clusters) : "cluster-${name}"],
    [for name in keys(var.replsets) : "replset-${name}"]
  ) : []
  vault_inventory = local.vault_enabled ? "\n[vault]\n${local.vault_host} ansible_host=${chaos_instance.vault[0].ip_address}\n\n[all:vars]\nvault_server=${chaos_instance.vault[0].ip_address}\nvault_environment=${var.prefix}\nvault_encryption=true\nvault_topologies_json='${jsonencode(local.vault_topologies)}'\nvault_controller_dir_override=${jsonencode(var.vault_controller_dir != "" ? abspath(var.vault_controller_dir) : abspath("${path.module}/../../ansible/.vault/chaos/${var.prefix}"))}\n" : ""
}

resource "chaos_instance" "vault" {
  count             = local.vault_enabled ? 1 : 0
  name              = local.vault_host
  os                = var.os_image
  cpu_cores         = var.vault_cpu_cores
  memory            = var.vault_memory_gb
  disk              = var.vault_volume_size
  ssh_user          = var.my_ssh_user
  description       = "${var.prefix} - MongoDB encryption key service"
  delete_after_days = var.delete_after_days
  firewall_rules = toset(concat(var.firewall_rules,
    length(var.firewall_rules) == 0 && var.source_ranges != "" ? [
      { source = var.source_ranges, port = "22", protocol = "tcp", comment = "SSH access" }
    ] : [],
    [
      { source = "10.30.0.0/16", port = "22", protocol = "tcp", comment = "Internal SSH" },
      { source = "10.30.0.0/16", port = "8200", protocol = "tcp", comment = "Internal Vault API" }
    ]
  ))
  lifecycle {
    precondition {
      condition = alltrue(concat(
        [for t in values(var.clusters) : (t.mongodb_distribution != "" ? t.mongodb_distribution : var.mongodb_distribution) == "psmdb"],
        [for t in values(var.replsets) : (t.mongodb_distribution != "" ? t.mongodb_distribution : var.mongodb_distribution) == "psmdb"]
      ))
      error_message = "Vault encryption is supported only for PSMDB topologies."
    }
  }
}

resource "local_file" "VaultInventory" {
  count    = local.vault_enabled ? 1 : 0
  filename = "${var.prefix}_inventory_vault"
  content  = "${local.vault_inventory}\n[all:vars]\nansible_user=${var.my_ssh_user}\nansible_ssh_private_key_file=${var.ssh_private_key_path}\nansible_ssh_common_args=-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null\n"
}
