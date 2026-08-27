################
# Project
################

variable "prefix" {
  type        = string
  default     = "ig"
  description = "Prefix to apply to resources to avoid naming collisions"
}

################
# Clusters and Replica Sets
################

variable "clusters" {
  description = "MongoDB clusters to deploy"
  type = map(object({
    env_tag              = optional(string, "test")
    configsvr_count      = optional(number, 3)
    shard_count          = optional(number, 2)
    shardsvr_replicas    = optional(number, 2)
    arbiters_per_replset = optional(number, 1)
    mongos_count         = optional(number, 2)
    bind_to_localhost    = optional(bool, false)
    enable_audit         = optional(bool, false)
    enable_tls           = optional(bool, false)
    audit_filter         = optional(string, "")
    mongodb_distribution = optional(string, "")
    mongo_release        = optional(string, "")
    mongo_version        = optional(string, "")
    mongo_repo           = optional(string, "")
    pbm_version          = optional(string, "")
    pbm_repo             = optional(string, "")
    pmm_client_version   = optional(string, "")
    pmm_client_repo      = optional(string, "")
    enable_pmm           = optional(bool, true)
    enable_pbm           = optional(bool, true)
    enable_mongot        = optional(bool, false)
    mongot_source        = optional(string, "")
    mongot_repo          = optional(string, "")
    mongot_version       = optional(string, "")
    ldap_server          = optional(string, "")
  }))
  default = {
    ig-cl01 = {
      env_tag = "test"
    }
  }
}

variable "replsets" {
  description = "MongoDB replica sets to deploy"
  type = map(object({
    env_tag                = optional(string, "test")
    data_nodes_per_replset = optional(number, 2)
    arbiters_per_replset   = optional(number, 1)
    bind_to_localhost      = optional(bool, false)
    enable_audit           = optional(bool, false)
    enable_tls             = optional(bool, false)
    audit_filter           = optional(string, "")
    mongodb_distribution   = optional(string, "")
    mongo_release          = optional(string, "")
    mongo_version          = optional(string, "")
    mongo_repo             = optional(string, "")
    pbm_version            = optional(string, "")
    pbm_repo               = optional(string, "")
    pmm_client_version     = optional(string, "")
    pmm_client_repo        = optional(string, "")
    enable_pmm             = optional(bool, true)
    enable_pbm             = optional(bool, true)
    enable_mongot          = optional(bool, false)
    mongot_source          = optional(string, "")
    mongot_repo            = optional(string, "")
    mongot_version         = optional(string, "")
    ldap_server            = optional(string, "")
  }))
  default = {
    #     ig-rs01 = {
    #     env_tag = "test"
    #     }
  }
}

variable "ldap_servers" {
  description = "LDAP servers to deploy. MongoDB clusters and replica sets select one with ldap_server."
  type = map(object({
    domain         = optional(string, "example.com")
    organization   = optional(string, "Example Inc")
    admin_password = optional(string, "admin")
    vm_size        = optional(string, "Standard_B2s")
    users          = optional(list(object({ uid = string, cn = string, sn = string, password = string })), [])
    mongodb_users  = optional(list(object({ user = string, roles = list(string) })), [])
  }))
  default = {}
}

################
# SSH & User Config
################

variable "my_ssh_user" {
  default     = "your_ssh_username"
  description = "User for SSH and configuration"
}

variable "ssh_private_key_path" {
  description = "Optional SSH private key file used by generated Ansible inventory and ssh_config. Empty uses ssh-agent/default SSH behavior."
  type        = string
  default     = ""
}

variable "ssh_users" {
  description = "User and public key map"
  type        = map(string)
  default = {
    your_ssh_username = "your_ssh_username.pub"
  }
}

variable "enable_ssh_gateway" {
  type        = bool
  default     = false
  description = "Enable SSH gateway/jump host"
}

variable "ssh_gateway_name" {
  type        = string
  default     = "gateway"
  description = "Jump host name for SSH gateway"
}

variable "port_to_forward" {
  type        = string
  default     = "23443"
  description = "Local port to forward for PMM UI access"
}

################
# PMM
################

variable "default_pmm_host" {
  description = "Base hostname for PMM"
  type        = string
  default     = "pmm-server"
}

locals {
  pmm_host = "${var.prefix}-${var.default_pmm_host}"
}

variable "pmm_disk_type" {
  default = "Premium_LRS" # Azure disk type equivalent to pd-ssd
}

variable "pmm_type" {
  default     = "Standard_D2s_v3"
  description = "Azure VM type for PMM server"
}

variable "pmm_volume_size" {
  default     = 100
  description = "Disk size in GB"
}

variable "pmm_port" {
  type    = number
  default = 8443
}

variable "pmm_image" {
  type        = string
  default     = "docker.io/percona/pmm-server:latest"
  description = "Docker image used by Ansible to run the PMM server container."
}

variable "enable_pmm" {
  type        = bool
  default     = true
  description = "Deploy a PMM monitoring server. Set to false to skip PMM entirely."
}

################
# TLS CA
################

variable "enable_tls" {
  type        = bool
  default     = false
  description = "Enable TLS and add a certificate authority host to generated inventories."
}

variable "ca_placement" {
  type        = string
  default     = "dedicated"
  description = "Place the TLS certificate authority on a dedicated VM or the PMM host."

  validation {
    condition     = contains(["dedicated", "pmm"], var.ca_placement)
    error_message = "ca_placement must be either dedicated or pmm."
  }

  validation {
    condition     = !var.enable_tls || var.ca_placement != "pmm" || var.enable_pmm
    error_message = "enable_pmm must be true when TLS is enabled with ca_placement set to pmm."
  }
}

variable "default_ca_host" {
  type        = string
  default     = "ca-server"
  description = "Base hostname for the dedicated CA VM."
}

variable "ca_type" {
  type        = string
  default     = "Standard_B1s"
  description = "Azure VM size for the dedicated CA VM."
}

locals {
  ca_host = "${var.prefix}-${var.default_ca_host}"
}

variable "enable_ycsb" {
  type        = bool
  default     = false
  description = "Deploy a dedicated YCSB workload generator instance."
}

variable "default_ycsb_host" {
  description = "Base hostname for YCSB"
  type        = string
  default     = "ycsb"
}

locals {
  ycsb_host = "${var.prefix}-${var.default_ycsb_host}"
}

variable "ycsb_type" {
  default     = "Standard_B2s"
  description = "Azure VM size for the YCSB server"
}

################
# Backup
################

variable "default_bucket_name" {
  description = "Base storage account/container name"
  type        = string
  default     = "mongo-bkp-storage"
}

locals {
  bucket_name      = "${var.prefix}${var.default_bucket_name}"
  storage_endpoint = "https://${local.bucket_name}.blob.core.windows.net"
}

variable "backup_retention" {
  default     = 2
  description = "Days to retain backup"
}

################
# VM Images
################

variable "image" {
  description = "Azure VM image definition"
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = optional(string, "latest")
  })
  default = {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }
}

variable "use_spot_instances" {
  type    = bool
  default = false
}

variable "data_disk_type" {
  default     = "Standard_LRS"
  description = "Azure managed disk type for MongoDB data disks (Standard_LRS, Premium_LRS, StandardSSD_LRS, UltraSSD_LRS)"
}

################
# Instance types
################

variable "shardsvr_type" {
  default     = "Standard_B2s"
  description = "Azure VM size for MongoDB shard servers"
}

variable "shardsvr_volume_size" {
  default     = 50
  description = "Managed disk size (GB) for MongoDB shard servers"
}

variable "configsvr_type" {
  default     = "Standard_B2s"
  description = "Azure VM size for MongoDB config servers (CSRS)"
}

variable "configsvr_volume_size" {
  default     = 20
  description = "Managed disk size (GB) for MongoDB config servers"
}

variable "mongos_type" {
  default     = "Standard_B2s"
  description = "Azure VM size for mongos router instances"
}

variable "arbiter_type" {
  default     = "Standard_B2s"
  description = "Azure VM size for MongoDB arbiter nodes"
}

variable "replsetsvr_type" {
  default     = "Standard_B2s"
  description = "Azure VM size for standalone replica set data-bearing nodes"
}

variable "replsetsvr_volume_size" {
  default     = 100
  description = "Managed disk size (GB) for standalone replica set data-bearing nodes"
}

################
# Networking
################

variable "default_resource_group_name" {
  type    = string
  default = "mongodb"
}

locals {
  resource_group_name = "${var.prefix}-${var.default_resource_group_name}"
}

variable "location" {
  type    = string
  default = "eastus"
}

variable "default_vnet_name" {
  description = "Base virtual network name"
  type        = string
  default     = "mongo-vnet"
}

locals {
  vnet_name = "${var.prefix}-${var.default_vnet_name}"
}

variable "subnet_name" {
  type    = string
  default = "mongo-subnet"
}

variable "subnet_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "source_ranges" {
  type    = string
  default = "0.0.0.0/0"
}
#############
# Package Versions
#############

variable "mongo_release" {
  type        = string
  default     = ""
  description = "MongoDB release line (e.g. psmdb-80, 8.0, 8.3). Empty string uses the default from group_vars."
}

variable "mongodb_distribution" {
  type        = string
  default     = ""
  description = "MongoDB distribution for non-Docker packages: psmdb, community, or enterprise. Empty string uses the default from group_vars."
}

variable "mongo_version" {
  type        = string
  default     = ""
  description = "Specific MongoDB version to install (e.g. 8.0.4). Empty string installs the latest available."
}

variable "mongo_repo" {
  type        = string
  default     = ""
  description = "Percona repository channel for MongoDB packages (release, testing, experimental). Empty string uses group_vars default."
}

variable "pbm_release" {
  type        = string
  default     = ""
  description = "Percona release channel for PBM (e.g. pbm). Empty string uses the default from group_vars."
}

variable "mongot_repo" {
  type        = string
  default     = ""
  description = "Percona repository channel for Percona Search packages (release, testing, experimental). Empty string uses group_vars default."
}

variable "pbm_version" {
  type        = string
  default     = ""
  description = "Specific PBM version to install (e.g. 2.4.0). Empty string installs the latest available."
}

variable "pbm_repo" {
  type        = string
  default     = ""
  description = "Percona repository channel for PBM packages (release, testing, experimental). Empty string uses group_vars default."
}

variable "pmm_client_version" {
  type        = string
  default     = ""
  description = "Specific PMM client version to install (e.g. 3.4.0). Empty string installs the latest available."
}

variable "pmm_client_repo" {
  type        = string
  default     = ""
  description = "Percona repository channel for PMM client packages (release, testing, experimental). Empty string uses group_vars default."
}
