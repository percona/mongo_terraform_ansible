################
# Project
################

variable "prefix" {
  type    = string
  default = "ig"
  description = "Prefix to be applied to the resources created, make sure to change it to avoid collisions with other users projects"
}

variable "rs_name" {
  description = "Name of the MongoDB replica set"
  default     = "rs01"
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

variable "data_nodes_per_replset" {
  type        = number
  default     = 2
  description = "How many data bearing nodes per replset"
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
  description = "Name of the replica set servers"
  default     = "mongodb-svr"
}

variable "replsetsvr_port" {
  type    = number
  default = 27017
}

variable "replsetsvr_volume_size" {
  type        = number
  default     = 20
  description = "Root disk size in GB for replica set data-bearing nodes"
}

variable "replsetsvr_cpu_cores" {
  type        = number
  default     = 2
  description = "Number of CPU cores for replica set data-bearing node instances"
}

variable "replsetsvr_memory_gb" {
  type        = number
  default     = 4
  description = "Memory in GB for replica set data-bearing node instances"
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
  default = 27017
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
