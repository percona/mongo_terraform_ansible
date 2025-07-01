################
# Project
################

variable "prefix" {
  type        = string
  default     = "ig"
  description = "Prefix to be applied to the resources created, make sure to change it to avoid collisions with other users' projects"
}

variable "cluster_name" {
  description = "Name of the MongoDB cluster"
  default     = "cluster01"
}

variable "env_tag" {
  default     = "qa"
  description = "Name of Environment"
}

variable "ssh_users" {
  description = "SSH user names, and the path to public key files on your machine to be added to authorized_keys"
  default = {
    ivan_groenewold = "ivan.pub"
  }
}

variable "my_ssh_user" {
  default     = "ivan_groenewold"
  description = "Used to auto-generate the ssh_config file. Each person running this code should set it to their own SSH user name"
}

##################
# MongoDB topology
##################

variable "configsvr_count" {
  default     = 3
  description = "Number of config servers to be used"
}

variable "shard_count" {
  default     = 2
  description = "Number of shards to be used"
}

variable "shardsvr_replicas" {
  default     = 2
  description = "How many data-bearing nodes per shard"
}

variable "arbiters_per_replset" {
  default     = 1
  description = "Number of arbiters per replica set"
}

variable "mongos_count" {
  default     = 1
  description = "Number of mongos to provision"
}

################
# Shards
################

variable "shardsvr_tag" {
  description = "Name of the shard servers"
  default     = "mongodb-shard"
}

variable "shardsvr_type" {
  default     = "Standard_D2s_v3"
  description = "Azure VM size of the shard server"
}

variable "shardsvr_volume_size" {
  default     = 50
  description = "Storage size (in GB) for the shard server"
}

variable "shard_port" {
  type    = number
  default = 27018
}

################
# Config Servers (CSRS)
################

variable "configsvr_tag" {
  description = "Name of the config servers"
  default     = "mongodb-cfg"
}

variable "configsvr_type" {
  default     = "Standard_D2s_v3"
  description = "Azure VM size of the config server"
}

variable "configsvr_volume_size" {
  default     = 20
  description = "Storage size (in GB) for the config server"
}

variable "configsvr_port" {
  type    = number
  default = 27019
}

################
# Mongos routers
################

variable "mongos_tag" {
  description = "Name of the mongos router servers"
  default     = "mongodb-mongos"
}

variable "mongos_type" {
  default     = "Standard_D2s_v3"
  description = "Azure VM size of the mongos servers"
}

variable "mongos_port" {
  type    = number
  default = 27017
}

#############
# Arbiters
#############

variable "arbiter_tag" {
  description = "Name of the arbiter servers"
  default     = "mongodb-arb"
}

variable "arbiter_type" {
  default     = "Standard_D2s_v3"
  description = "Azure VM size of the arbiter server"
}

variable "arbiter_port" {
  type    = number
  default = 27018
}

#############
# Instances
#############

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
  description = "Azure disk storage type (Standard_LRS, Premium_LRS, etc.)"
}

#############
# Networking
#############

variable "resource_group_name" {
  type    = string
  default = "mongodb"
}

variable "location" {
  type    = string
  default = "eastus"
  description = "Azure region (e.g., eastus, westus2, etc.)"
}

variable "vnet_name" {
  type    = string
  default = "mongo-terraform"
}

variable "subnet" {
  type    = string
  default = "mongo-subnet"
}

variable "subnet_cidr" {
  type    = string
  default = "10.0.0.0/20"
}

variable "source_ranges" {
  type    = string
  default = "0.0.0.0/0"
  description = "CIDR range to allow traffic from (for NSG rules)"
}