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
    audit_filter         = optional(string, "")
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
    audit_filter           = optional(string, "")
  }))
  default = {
    #     ig-rs01 = {
    #     env_tag = "test"
    #     }
  }
}

################
# SSH & User Config
################

variable "my_ssh_user" {
  default     = "ivan_groenewold"
  description = "User for SSH and configuration"
}

variable "ssh_users" {
  description = "User and public key map"
  type        = map(string)
  default = {
    ivan_groenewold = "ivan.pub"
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

variable "enable_pmm" {
  type        = bool
  default     = true
  description = "Deploy a PMM monitoring server. Set to false to skip PMM entirely."
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
  description = "Percona release channel for MongoDB (e.g. psmdb-80). Empty string uses the default from group_vars."
}

variable "mongo_version" {
  type        = string
  default     = ""
  description = "Specific MongoDB version to install (e.g. 8.0.4). Empty string installs the latest available."
}

variable "pbm_release" {
  type        = string
  default     = ""
  description = "Percona release channel for PBM (e.g. pbm). Empty string uses the default from group_vars."
}

variable "pbm_version" {
  type        = string
  default     = ""
  description = "Specific PBM version to install (e.g. 2.4.0). Empty string installs the latest available."
}

variable "pmm_client_version" {
  type        = string
  default     = ""
  description = "Specific PMM client version to install (e.g. 3.4.0). Empty string installs the latest available."
}
