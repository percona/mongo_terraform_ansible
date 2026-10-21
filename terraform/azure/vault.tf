variable "vault_type" {
  type    = string
  default = "Standard_B1ms"
}

variable "vault_volume_size" {
  type    = number
  default = 64
}

variable "vault_controller_dir" {
  type    = string
  default = ""
}

module "vault_mode_guard" {
  source         = "../modules/vault_mode_guard"
  controller_dir = var.vault_controller_dir != "" ? abspath(var.vault_controller_dir) : abspath("${path.module}/../../ansible/.vault/azure/${var.prefix}")
  topologies     = merge({ for n in keys(var.clusters) : "cluster-${n}" => var.vault_encryption }, { for n in keys(var.replsets) : "replset-${n}" => var.vault_encryption })
  enabled        = var.vault_encryption
}

module "vault_recovery" {
  count          = local.vault_enabled ? 1 : 0
  source         = "../modules/vault_recovery"
  controller_dir = var.vault_controller_dir != "" ? var.vault_controller_dir : "${path.module}/../../ansible/.vault/azure/${var.prefix}"
}

locals {
  vault_host    = "${var.prefix}-vault"
  vault_enabled = var.vault_encryption && length(var.clusters) + length(var.replsets) > 0
  vault_topologies = local.vault_enabled ? concat(
    [for name in keys(var.clusters) : "cluster-${name}"],
    [for name in keys(var.replsets) : "replset-${name}"]
  ) : []
  vault_inventory = local.vault_enabled ? "\n[vault]\n${local.vault_host} ansible_host=${azurerm_linux_virtual_machine.vault[0].public_ip_address}\n\n[all:vars]\nvault_server=${azurerm_network_interface.vault[0].private_ip_address}\nvault_environment=${var.prefix}\nvault_encryption=true\nvault_topologies_json='${jsonencode(local.vault_topologies)}'\nvault_controller_dir_override=${jsonencode(var.vault_controller_dir != "" ? abspath(var.vault_controller_dir) : abspath("${path.module}/../../ansible/.vault/azure/${var.prefix}"))}\n" : ""
}

resource "azurerm_public_ip" "vault" {
  count               = local.vault_enabled ? 1 : 0
  name                = "${local.vault_host}-public-ip"
  location            = var.location
  resource_group_name = local.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  depends_on          = [time_sleep.wait_after_rg]
}

resource "azurerm_network_interface" "vault" {
  count               = local.vault_enabled ? 1 : 0
  name                = "${local.vault_host}-nic"
  location            = var.location
  resource_group_name = local.resource_group_name
  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vault[0].id
  }
  depends_on = [time_sleep.wait_after_rg]
}

resource "azurerm_linux_virtual_machine" "vault" {
  count                 = local.vault_enabled ? 1 : 0
  name                  = local.vault_host
  location              = var.location
  resource_group_name   = local.resource_group_name
  size                  = var.vault_type
  admin_username        = var.my_ssh_user
  network_interface_ids = [azurerm_network_interface.vault[0].id]
  admin_ssh_key {
    username   = var.my_ssh_user
    public_key = file(var.ssh_users[var.my_ssh_user])
  }
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = var.vault_volume_size
  }
  source_image_reference {
    publisher = var.image.publisher
    offer     = var.image.offer
    sku       = var.image.sku
    version   = try(var.image.version, "latest")
  }
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
