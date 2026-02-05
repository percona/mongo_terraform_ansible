terraform {
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "0.8.3"
    }
  }
}

provider "libvirt" {
# uri = "qemu:///system?socket=/run/libvirt/libvirt-sock"
  uri = "qemu:///system"
} 

resource "libvirt_pool" "k8s" {
  name = "k8s"
  type = "dir"
  path = abspath("${path.module}/pool")
}

resource "libvirt_volume" "os_image" {
  name   = "os_image"
  pool   = libvirt_pool.k8s.name
  source = "${path.module}/${var.source_vm}"
  format = "qcow2"
}

resource "libvirt_volume" "disk_resized" {
  name           = "disk"
  pool           = libvirt_pool.k8s.name
  base_volume_id = "${libvirt_volume.os_image.id}"
  size           = 20000000000 # 20GiB
}

resource "libvirt_volume" "worker" {
  name           = "worker_${count.index}.qcow2"
  pool           = libvirt_pool.k8s.name
  base_volume_id = "${libvirt_volume.disk_resized.id}"
  count          = var.hosts
}

resource "libvirt_cloudinit_disk" "commoninit" { 
  count     = var.hosts
  name      = "commoninit-rocky_${var.hostnames[count.index]}.iso"
  pool      = libvirt_pool.k8s.name
  user_data = templatefile("${path.module}/templates/user_data.tpl", 
  {
      host_name = var.hostnames[count.index]
      auth_key  = file("${path.module}/ssh_keys/opentofu.pub")
  }) 
     network_config =   templatefile("${path.module}/templates/network_config.tpl", {
     interface = var.interface
     ip_addr   = var.ips[count.index]
  })
}

resource "libvirt_network" "priv" {
  # the name used by libvirt
  name = "priv"

  # mode can be: "nat" (default), "none", "route", "open", "bridge"
  mode = "nat"

  #  the domain used by the DNS server in this network
  domain = "default.local"

  dns {
    enabled = true
    local_only = true
  }

  #  list of subnets the addresses allowed for domains connected
  # also derived to define the host addresses
  # also derived to define the addresses served by the DHCP server
  addresses = ["192.168.100.0/24"]
}

resource "libvirt_domain" "domain-distro" {
  count  = var.hosts
  name   = "${var.hostnames[count.index]}"
  memory = var.memory[count.index]
  vcpu   = var.vcpu  
  cloudinit = element(libvirt_cloudinit_disk.commoninit.*.id, count.index)
  
  network_interface {
      network_name = "priv"
      addresses    = [var.ips[count.index]]
  }  
  console {
      type        = "pty"
      target_port = "0"
      target_type = "serial"
  }  
  console {
      type        = "pty"
      target_port = "1"
      target_type = "virtio"
  }  

  graphics {
    type        = "vnc"
    listen_type = "address"
  }

  cpu {
    mode = "host-passthrough"
  }
  disk {
    volume_id = element(libvirt_volume.worker.*.id, count.index)
  }
}

resource "null_resource" "shutdowner" {
  # iterate with for_each over Vms list ( my *.tf file creates VMs from list)
  for_each = toset(var.hostnames)
  triggers = {
    trigger = var.vm_condition_poweron
  }

  provisioner "local-exec" {
    command = var.vm_condition_poweron?"echo 'do nothing'":"virsh -c qemu:///system shutdown ${each.value}"
  }
}

variable "vm_condition_poweron" {
  default = true
}

