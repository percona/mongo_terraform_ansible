terraform {
  backend "local" {}

  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "0.9.7"
    }
  }
}

provider "libvirt" {
  uri = "qemu:///system"
}

locals {
  is_arm  = var.arch == "aarch64"
  machine = local.is_arm ? "virt" : "pc"
}

resource "libvirt_pool" "k8s" {
  name = "k8s"
  type = "dir"
  target = {
    path = abspath("${path.module}/pool")
  }
}

resource "libvirt_volume" "os_image" {
  name = "os_image"
  pool = libvirt_pool.k8s.name
  create = {
    content = {
      url = "file://${abspath("${path.module}/${var.source_vm}")}"
    }
  }
  target = {
    format = {
      type = "qcow2"
    }
  }
}

resource "libvirt_volume" "disk_resized" {
  name          = "disk"
  pool          = libvirt_pool.k8s.name
  capacity      = 20000000000
  capacity_unit = "B"
  backing_store = {
    path = libvirt_volume.os_image.path
    format = {
      type = "qcow2"
    }
  }
  target = {
    format = {
      type = "qcow2"
    }
  }
}

resource "libvirt_volume" "worker" {
  count         = var.hosts
  name          = "worker_${count.index}.qcow2"
  pool          = libvirt_pool.k8s.name
  capacity      = 20000000000
  capacity_unit = "B"
  backing_store = {
    path = libvirt_volume.disk_resized.path
    format = {
      type = "qcow2"
    }
  }
  target = {
    format = {
      type = "qcow2"
    }
  }
}

resource "libvirt_cloudinit_disk" "commoninit" {
  count   = var.hosts
  name    = "commoninit_${var.hostnames[count.index]}"
  user_data = templatefile("${path.module}/templates/user_data.tpl", {
    host_name = var.hostnames[count.index]
    auth_key  = file("${path.module}/ssh_keys/opentofu.pub")
  })
  meta_data = yamlencode({
    instance-id    = var.hostnames[count.index]
    local-hostname = var.hostnames[count.index]
  })
  network_config = templatefile("${path.module}/templates/network_config.tpl", {
    interface = var.interface
    ip_addr   = var.ips[count.index]
  })
}

resource "libvirt_volume" "cloudinit_vol" {
  count = var.hosts
  name  = "commoninit_${var.hostnames[count.index]}.iso"
  pool  = libvirt_pool.k8s.name
  create = {
    content = {
      url = libvirt_cloudinit_disk.commoninit[count.index].path
    }
  }
}

resource "libvirt_network" "priv" {
  name      = "priv"
  autostart = true
  forward = {
    mode = "nat"
  }
  domain = {
    name       = "default.local"
    local_only = "yes"
  }
  ips = [
    {
      address = "192.168.100.1"
      netmask = "255.255.255.0"
    }
  ]
}

# Pre-create NVRAM files from the template so libvirt can write UEFI variables.
# Required for aarch64 UEFI domains — without a pre-seeded NVRAM file the
# domain definition fails because libvirt cannot create one at define time.
resource "null_resource" "nvram_init" {
  for_each = local.is_arm && var.nvram_template != "" ? toset(var.hostnames) : toset([])

  provisioner "local-exec" {
    command = "cp -n ${var.nvram_template} /var/lib/libvirt/qemu/nvram/${each.value}_VARS.fd && chmod 0660 /var/lib/libvirt/qemu/nvram/${each.value}_VARS.fd"
  }
}

resource "libvirt_domain" "domain-distro" {
  count       = var.hosts
  name        = var.hostnames[count.index]
  memory      = var.memory[count.index]
  memory_unit = "MiB"
  vcpu        = var.vcpu
  type        = var.domain_type

  depends_on = [null_resource.nvram_init]

  os = {
    type         = "hvm"
    type_arch    = var.arch
    type_machine = local.machine
    loader          = local.is_arm && var.firmware != "" ? var.firmware : null
    loader_type     = local.is_arm && var.firmware != "" ? "pflash" : null
    loader_readonly = local.is_arm && var.firmware != "" ? "yes" : null
    nv_ram = local.is_arm && var.nvram_template != "" ? {
      nv_ram = "/var/lib/libvirt/qemu/nvram/${var.hostnames[count.index]}_VARS.fd"
    } : null
  }

  devices = {
    consoles = [
      {
        type = "pty"
        target = {
          type = "serial"
          port = 0
        }
      }
    ]

    disks = [
      {
        source = {
          volume = {
            pool   = libvirt_pool.k8s.name
            volume = libvirt_volume.worker[count.index].name
          }
        }
        target = {
          dev = "vda"
          bus = "virtio"
        }
      },
      {
        source = {
          volume = {
            pool   = libvirt_pool.k8s.name
            volume = libvirt_volume.cloudinit_vol[count.index].name
          }
        }
        target = {
          dev = local.is_arm ? "vdb" : "sda"
          bus = local.is_arm ? "virtio" : "sata"
        }
        readonly = true
      }
    ]

    interfaces = [
      {
        model = {
          type = "virtio"
        }
        source = {
          network = {
            network = libvirt_network.priv.name
          }
        }
      }
    ]
  }
}

resource "null_resource" "starter" {
  count = var.hosts
  triggers = {
    domain_id = libvirt_domain.domain-distro[count.index].id
  }

  provisioner "local-exec" {
    command = "virsh -c qemu:///system start ${var.hostnames[count.index]} || true"
  }
}

resource "null_resource" "shutdowner" {
  for_each = toset(var.hostnames)
  triggers = {
    trigger = var.vm_condition_poweron
  }

  provisioner "local-exec" {
    command = var.vm_condition_poweron ? "echo 'do nothing'" : "virsh -c qemu:///system shutdown ${each.value}"
  }
}
