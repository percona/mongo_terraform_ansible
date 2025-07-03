################
# Project
################

variable "prefix" {
  type        = string
  default     = "ig"
  description = "Prefix to be applied to the resources created. Change it to avoid naming collisions."
}

variable "rs_name" {
  description = "Name of the MongoDB replica set"
  default     = "rs01"
}

variable "env_tag" {
  default     = "test"
  description = "Name of the environment"
}

variable "ssh_users" {
  description = "Map of SSH usernames and the path to their public key files on your machine"
  type        = map(string)
  default = {
    ivan_groenewold = "ivan.pub"
  }
}

variable "my_ssh_user" {
  default     = "ivan_groenewold"
  description = "Used to generate the ssh_config file"
}

##################
# MongoDB topology
##################

variable "data_nodes_per_replset" {
  type        = number
  default     = 2
  description = "Number of data-bearing nodes per replica set"
}

variable "arbiters_per_replset" {
  type        = number
  default     = 1
  description = "Number of arbiters per replica set"
}

######################
# Data bearing members
######################

variable "replset_tag" {
  description = "Name prefix for the replica set servers"
  default     = "mongodb-svr"
}

variable "replsetsvr_port" {
  type        = number
  default     = 27017
}

variable "replsetsvr_volume_size" {
  type        = number
  default     = 100
  description = "Storage size (in GB) for replica set data disks"
}

variable "replsetsvr_type" {
  type        = string
  default     = "Standard_B2s"
  description = "Azure VM size for replica set members"
}

#############
# Arbiters
#############

variable "arbiter_tag" {
  description = "Name prefix for arbiter servers"
  default     = "mongodb-arb"
}

variable "arbiter_type" {
  type        = string
  default     = "Standard_B2s"
  description = "Azure VM size for arbiter nodes"
}

variable "arbiter_port" {
  type        = number
  default     = 27017
}

#############
# Instances
#############

variable "image" {
  description = "Azure VM image reference"
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
  type        = bool
  default     = false
  description = "Use spot instances to save cost (may be evicted)"
}

variable "data_disk_type" {
  type        = string
  default     = "Standard_LRS"
  description = "Azure managed disk type: Standard_LRS, Premium_LRS, etc."
}

#############
# Networking
#############

variable "resource_group_name" {
  type        = string
  default     = "mongodb"
}

variable "location" {
  type        = string
  default     = "eastus" # Azure region, e.g. eastus, westeurope
}

variable "vnet_name" {
  type        = string
  default     = "mongo-terraform"
}

variable "subnet" {
  type        = string
  default     = "mongo-subnet"
}

variable "subnet_cidr" {
  type        = string
  default     = "10.128.0.0/20"
}

variable "source_ranges" {
  type    = string
  default = "0.0.0.0/0"
}