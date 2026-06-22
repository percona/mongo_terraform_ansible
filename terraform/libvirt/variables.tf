variable "hosts" {
  type    = number
  default = 3
}

variable "hostnames" {
  type    = list(any)
  default = ["db-1", "db-2", "db-3"]
}

variable "interface" {
  type    = string
  default = "ens01"
}

variable "source_vm" {
  type    = string
  default = "sources/rocky9.qcow2"
}

variable "memory" {
  type    = list(any)
  default = [2048, 2048, 2048]
}

variable "vcpu" {
  type    = number
  default = 2
}

variable "distros" {
  type    = list(any)
  default = ["rocky"]
}

variable "ips" {
  type    = list(any)
  default = ["192.168.100.10", "192.168.100.11", "192.168.100.12"]
}

variable "auth_key" {
  type    = string
  default = ""
}

variable "vm_condition_poweron" {
  default = true
}

variable "domain_type" {
  type    = string
  default = "qemu"
}

variable "arch" {
  type    = string
  default = "x86_64"
  validation {
    condition     = contains(["x86_64", "aarch64"], var.arch)
    error_message = "arch must be x86_64 or aarch64."
  }
}

variable "firmware" {
  type    = string
  default = ""
  # aarch64 Ubuntu/Debian host: /usr/share/AAVMF/AAVMF_CODE.fd
  # aarch64 RHEL/Rocky host:    /usr/share/edk2/aarch64/QEMU_EFI-pflash.raw
}

variable "nvram_template" {
  type    = string
  default = ""
  # aarch64 Ubuntu/Debian host: /usr/share/AAVMF/AAVMF_VARS.fd
  # aarch64 RHEL/Rocky host:    /usr/share/edk2/aarch64/vars-template-pflash.raw
}
