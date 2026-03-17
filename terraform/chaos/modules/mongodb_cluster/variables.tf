################
# Project
################

variable "prefix" {
  type    = string
  default = "ig"
  description = "Prefix to be applied to the resources created, make sure to change it to avoid collisions with other users projects"
}

variable "cluster_name" {
  description = "Name of the MongoDB cluster"
  default     = "cluster01"
}

variable "env_tag" {
  default     = "qa"
  description = "Name of Environment"
}

variable "my_ssh_user" {
  default     = "ivan_groenewold"
  description = "Used to auto-generate the ssh_config file. Each person running this code should set it to its own SSH user name"
}

##################
# MongoDB topology
##################

variable "configsvr_count" {
  type        = number
  default     = 3
  description = "Number of config servers to be used"
}

variable "shard_count" {
  type        = number
  default     = 2
  description = "Number of shards to be used"
}

variable "shardsvr_replicas" {
  type        = number
  default     = 2
  description = "How many data bearing nodes per shard"
}

variable "arbiters_per_replset" {
  type        = number
  default     = 1
  description = "Number of arbiters per replica set"
}

variable "mongos_count" {
  type        = number
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

variable "shardsvr_cpu_cores" {
  type        = number
  default     = 2
  description = "Number of CPU cores for shard server instances"
}

variable "shardsvr_memory_gb" {
  type        = number
  default     = 4
  description = "Memory in GB for shard server instances"
}

variable "shardsvr_volume_size" {
  type        = number
  default     = 20
  description = "Root disk size in GB for shard server instances"
}

variable "shard_port" {
  type    = number
  default = 27018
}

################
# CSRS
################

variable "configsvr_tag" {
  description = "Name of the config servers"
  default     = "mongodb-cfg"
}

variable "configsvr_cpu_cores" {
  type        = number
  default     = 2
  description = "Number of CPU cores for config server instances"
}

variable "configsvr_memory_gb" {
  type        = number
  default     = 4
  description = "Memory in GB for config server instances"
}

variable "configsvr_volume_size" {
  type        = number
  default     = 20
  description = "Root disk size in GB for config server instances"
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

variable "mongos_cpu_cores" {
  type        = number
  default     = 2
  description = "Number of CPU cores for mongos router instances"
}

variable "mongos_memory_gb" {
  type        = number
  default     = 4
  description = "Memory in GB for mongos router instances"
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

variable "arbiter_cpu_cores" {
  type        = number
  default     = 2
  description = "Number of CPU cores for arbiter instances"
}

variable "arbiter_memory_gb" {
  type        = number
  default     = 4
  description = "Memory in GB for arbiter instances"
}

variable "arbiter_port" {
  type    = number
  default = 27018
}

#############
# Instances
#############

variable "os_image" {
  description = "Operating system image for all instances"
  type        = string
  default     = "Ubuntu 24.04"
}

variable "delete_after_days" {
  type        = number
  default     = 14
  description = "Number of days before instances are automatically deleted"
}

#############
# Networking
#############


variable "source_ranges" {
  type        = string
  default     = ""
  description = "CIDR range for firewall rules. Leave empty for no firewall rules."
}

variable "firewall_rules" {
  type = list(object({
    source   = string
    port     = string
    protocol = string
    comment  = string
  }))
  default     = []
  description = "Custom firewall rules (CIDR+port) that override source_ranges when non-empty."
}
