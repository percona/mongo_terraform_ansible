################
# Project
################

variable "prefix" {
  type    = string
  default = "ig"
  description = "Prefix to be applied to the resources created, make sure to change it to avoid collisions with other users projects"
}

# By default we deploy 1 sharded cluster, named ig-cl01. Make sure to change the default name and prefix (ig-cl01) to avoid duplicates. The configuration can be customized by adding the optional values listed.
variable "clusters" {
  description = "MongoDB clusters to deploy"
  type = map(object({
    env_tag               = optional(string, "test")                # Name of Environment for the cluster
    configsvr_count       = optional(number, 3)                     # Number of config servers to be used
    shard_count           = optional(number, 2)                     # Number of shards to be used
    shardsvr_replicas     = optional(number, 2)                     # How many data bearing nodes per shard
    arbiters_per_replset  = optional(number, 1)                     # Number of arbiters per replica set
    mongos_count          = optional(number, 2)                     # Number of mongos to provision
  }))

  default = {
    ig-cl01 = {
      env_tag = "test"
    }
#    ig-cl02 = {
#      env_tag = "prod"
#      mongos_count = 1
#   }
  }
}

# By default, no replica sets are deployed (except those needed for the sharded clusters).
# If you want to provision separate replica sets, uncomment the default below. Make sure to change the default name and prefix (ig-rs01) to avoid duplicates. 
variable "replsets" {
  description = "MongoDB replica sets to deploy"
  type = map(object({
    env_tag                = optional(string, "test")               # Name of Environment
    data_nodes_per_replset = optional(number, 2)                    # Number of data bearing members per replset
    arbiters_per_replset   = optional(number, 1)                    # Number of arbiters per replica set
  })) 

  default = {
#    ig-rs01 = {
#      env_tag = "test"
#    }
#    ig-rs02 = {
#      env_tag = "prod"
#    }
  }
}

variable "ssh_public_key_path" {
  description = "SSH public key file to be added to authorized_keys"
  default =  "ivan.pub"
}

variable "my_ssh_user" {
  default = "ec2-user" # For Centos AMIs
  #default = "ubuntu" # For Ubuntu AMIs
  description = "Used to auto-generate the ssh_config file. Each person running this code should set it to its own SSH user name"  
}

variable "default_key_pair" {
  description = "Base key pair name"
  type        = string
  default     = "key"
}

locals {
  my_key_pair = "${var.prefix}-${var.my_ssh_user}-${var.default_key_pair}"
}

variable "enable_ssh_gateway" {
  type = bool
  default = false
  description = "Adds proxycommand lines with a gateway/jump host to the generated ssh_config file"
}

variable "ssh_gateway_name" {
  type = string
  default = "gateway"
  description = "Name of your jump host to use for ssh_config"
}

variable "port_to_forward" {
  type = string
  default = "23443"
  description = "Local port number to forward via SSH to access PMM UI over localhost"
}

#############
# PMM
#############

variable "default_pmm_host" {
  description = "Base PMM host name"
  type        = string
  default     = "pmm-server"
}

locals {
  pmm_host = "${var.prefix}-${var.default_pmm_host}"
}

variable "pmm_disk_type" {
   default = "gp2"
}

variable "pmm_type" {
  default = "t3.large"
  description = "instance type of the PMM server"
}

variable "pmm_volume_size" {
  default = "100"
  description = "storage size for the PMM server"
}

variable "pmm_port" {
  type = number
  default = 8443
}

#############
# Backup
#############

locals {
  storage_endpoint = "https://s3.${var.region}.amazonaws.com"
}

variable "default_bucket_name" {
  description = "Base bucket name"
  type        = string
  default     = "mongo-bkp-storage"
}

locals {
  bucket_name = "${var.prefix}-${var.default_bucket_name}"
}

variable "backup_retention" {
  default = "2"
  description = "days to keep backups in bucket"
}

#############
# Instances
#############

variable "image" {
  description = "Available images by region"
  default = {
    us-west-2 = "ami-0ad8bfd4b10994785" # Centos 9
    #us-west-2 = "ami-04999cd8f2624f834" # AL2023
    #us-west-2 = "ami-075686beab831bb7f" # Ubuntu 24.04
  }
}

# Save money by running spot instances but they may be terminated by AWS at any time
variable "use_spot_instances" {
  type = bool
  default = false
}

variable "data_disk_type" {
  default = "gp2"
}

#############
# Networking
#############

variable "region" {
  type    = string
  default = "us-west-2"
}

variable "default_vpc_name" {
  description = "Base VPC name"
  type        = string
  default     = "mongo"
}

locals {
  vpc = "${var.prefix}-${var.default_vpc_name}"
}

variable "subnet_count" {
  type = number
  default = 3
  description = "How many subnets to create"
}

variable "subnet_cidr" {
  type    = string
  default = "10.128.0.0/20"
}

# source IPs that will connect to the cluster from outside the VPC
variable "source_ranges" {
  type    = string
  default = "0.0.0.0/0"
}
