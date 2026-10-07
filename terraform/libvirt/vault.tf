# Libvirt provisions base VMs. Merge this inventory with the manually maintained
# MongoDB inventory; map each enabled topology namespace to its data-bearing hosts.
variable "vault_topologies" {
  type    = map(set(string))
  default = {}
  validation {
    condition     = alltrue([for name in keys(var.vault_topologies) : can(regex("^(cluster|replset)-[A-Za-z0-9_-]+$", name))])
    error_message = "Vault topology names must be cluster-<name> or replset-<name>."
  }
  validation {
    condition     = length(flatten([for hosts in values(var.vault_topologies) : tolist(hosts)])) == length(distinct(flatten([for hosts in values(var.vault_topologies) : tolist(hosts)])))
    error_message = "A data-bearing host can belong to only one encrypted topology."
  }
}
variable "vault_encryption" {
  type    = bool
  default = false
}
variable "vault_environment" {
  type    = string
  default = "libvirt"
  validation {
    condition     = can(regex("^[A-Za-z0-9_-]+$", var.vault_environment))
    error_message = "vault_environment must be a filesystem-safe environment identifier."
  }
}
variable "vault_ip" {
  type    = string
  default = "192.168.100.20"
}
variable "vault_memory_mb" {
  type    = number
  default = 2048
}
variable "vault_controller_dir" {
  type    = string
  default = ""
}

module "vault_mode_guard" {
  source         = "../modules/vault_mode_guard"
  controller_dir = var.vault_controller_dir != "" ? abspath(var.vault_controller_dir) : abspath("${path.module}/../../ansible/.vault/libvirt/${var.vault_environment}")
  topologies     = { for name in keys(var.vault_topologies) : name => var.vault_encryption }
  enabled        = var.vault_encryption
}

locals {
  vault_enabled    = var.vault_encryption && length(var.vault_topologies) > 0
  vault_topologies = local.vault_enabled ? var.vault_topologies : {}
  vault_host       = "${var.vault_environment}-vault"
}

resource "terraform_data" "vault_topology_validation" {
  input = var.vault_topologies
  lifecycle {
    precondition {
      condition     = !var.vault_encryption || length(var.vault_topologies) > 0
      error_message = "vault_encryption requires at least one topology in vault_topologies."
    }
  }
}

resource "libvirt_volume" "vault" {
  count         = local.vault_enabled ? 1 : 0
  name          = "${local.vault_host}.qcow2"
  pool          = libvirt_pool.k8s.name
  capacity      = 20000000000
  capacity_unit = "B"
  backing_store = {
    path   = libvirt_volume.disk_resized.path
    format = { type = "qcow2" }
  }
  target = { format = { type = "qcow2" } }
}

resource "libvirt_cloudinit_disk" "vault" {
  count = local.vault_enabled ? 1 : 0
  name  = "${local.vault_host}-init"
  user_data = templatefile("${path.module}/templates/user_data.tpl", {
    host_name = local.vault_host
    auth_key  = local.auth_key
  })
  meta_data = yamlencode({ instance-id = local.vault_host, local-hostname = local.vault_host })
  network_config = templatefile("${path.module}/templates/network_config.tpl", {
    interface = var.interface
    ip_addr   = var.vault_ip
  })
}

resource "libvirt_volume" "vault_init" {
  count = local.vault_enabled ? 1 : 0
  name  = "${local.vault_host}-init.iso"
  pool  = libvirt_pool.k8s.name
  create = {
    content = { url = libvirt_cloudinit_disk.vault[0].path }
  }
}

resource "null_resource" "vault_nvram" {
  count = local.vault_enabled && local.is_arm && var.nvram_template != "" ? 1 : 0
  provisioner "local-exec" {
    command = "cp -n ${var.nvram_template} /var/lib/libvirt/qemu/nvram/${local.vault_host}_VARS.fd && chmod 0660 /var/lib/libvirt/qemu/nvram/${local.vault_host}_VARS.fd"
  }
}

resource "libvirt_domain" "vault" {
  count       = local.vault_enabled ? 1 : 0
  name        = local.vault_host
  memory      = var.vault_memory_mb
  memory_unit = "MiB"
  vcpu        = 2
  type        = var.domain_type
  os = {
    type            = "hvm"
    type_arch       = var.arch
    type_machine    = local.machine
    loader          = local.is_arm && var.firmware != "" ? var.firmware : null
    loader_type     = local.is_arm && var.firmware != "" ? "pflash" : null
    loader_readonly = local.is_arm && var.firmware != "" ? "yes" : null
    nv_ram = local.is_arm && var.nvram_template != "" ? {
      nv_ram = "/var/lib/libvirt/qemu/nvram/${local.vault_host}_VARS.fd"
    } : null
  }
  devices = {
    consoles = [{ type = "pty", target = { type = "serial", port = 0 } }]
    disks = [
      {
        source = { volume = { pool = libvirt_pool.k8s.name, volume = libvirt_volume.vault[0].name } }
        target = { dev = "vda", bus = "virtio" }
      },
      {
        source   = { volume = { pool = libvirt_pool.k8s.name, volume = libvirt_volume.vault_init[0].name } }
        target   = { dev = local.is_arm ? "vdb" : "sda", bus = local.is_arm ? "virtio" : "sata" }
        readonly = true
      }
    ]
    interfaces = [{ model = { type = "virtio" }, source = { network = { network = libvirt_network.priv.name } } }]
  }
  depends_on = [null_resource.vault_nvram, terraform_data.vault_topology_validation]
  lifecycle {
    precondition {
      condition     = local.auth_key != ""
      error_message = "Set auth_key to an SSH public key or provide ssh_keys/opentofu.pub."
    }
    precondition {
      condition     = !contains(var.ips, var.vault_ip)
      error_message = "vault_ip must not overlap a MongoDB VM address."
    }
  }
}

resource "null_resource" "vault_start" {
  count    = local.vault_enabled ? 1 : 0
  triggers = { domain_id = libvirt_domain.vault[0].id }
  provisioner "local-exec" {
    command = "virsh -c qemu:///system start ${local.vault_host} || true"
  }
}

resource "local_file" "vault_inventory" {
  count    = local.vault_enabled ? 1 : 0
  filename = "${var.vault_environment}_inventory_vault.yml"
  content = yamlencode({ all = {
    vars = {
      vault_environment             = var.vault_environment
      vault_controller_dir_override = var.vault_controller_dir != "" ? abspath(var.vault_controller_dir) : abspath("${path.module}/../../ansible/.vault/libvirt/${var.vault_environment}")
      vault_server                  = var.vault_ip
      vault_encryption              = var.vault_encryption
      vault_topologies_json         = jsonencode(keys(local.vault_topologies))
      ansible_user                  = "admin"
    }
    children = { vault = { hosts = { (local.vault_host) = { ansible_host = var.vault_ip } } } }
    hosts = merge({}, [for topology, hosts in local.vault_topologies : {
      for host in hosts : host => {
        vault_encryption     = var.vault_encryption
        vault_topology       = topology
        mongodb_distribution = "psmdb"
      }
    }]...)
  } })
}

module "vault_recovery" {
  count          = local.vault_enabled ? 1 : 0
  source         = "../modules/vault_recovery"
  controller_dir = var.vault_controller_dir != "" ? var.vault_controller_dir : "${path.module}/../../ansible/.vault/libvirt/${var.vault_environment}"
}
