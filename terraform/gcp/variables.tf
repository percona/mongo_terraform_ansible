################
# Project
################

variable "prefix" {
  type    = string
  default = "ig"
  description = "Prefix to be applied to the resources created, make sure to change it to avoid collisions with other users projects"
}

variable "project_id" {
  type    = string
  default = "gs-techleads"
  description = "GCP project name. Replace with the project your GCP account belongs to"
}

# By default we deploy 1 sharded cluster, named ig01-s01. Make sure to change the default name (ig01-s01) to avoid duplicates. The configuration can be customized by adding the optional values listed.
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
# If you want to provision separate replica sets, uncomment the default below. Make sure to change the default names (ig01-rs01) to avoid duplicates. 
variable "replsets" {
   description = "MongoDB replica sets to deploy"
   type = map(object({
     env_tag                   = optional(string, "test")               # Name of Environment
     data_nodes_per_replset    = optional(number, 2)                    # Number of data bearing members per replset
     arbiters_per_replset      = optional(number, 1)                    # Number of arbiters per replica set
   })) 

   default = {
#     ig-rs01 = {
#       env_tag = "test"
#     }
#     ig-rs02 = {
#       env_tag = "prod"
#     }
   }
}

variable "gce_ssh_users" {
  description = "SSH user names, and their public key files to be added to authorized_keys"
  default = {
    ivan_groenewold = "ivan.pub"
#    ,user2 = "user2.pub"
  }
}

variable "my_ssh_user" {
  default = "ivan_groenewold"
  description = "Used to auto-generate the ssh_config file. Each person running this code should set it to its own SSH user name"  
}

variable "enable_ssh_gateway" {
  type = bool
  default = false
  description = "Adds proxycommand lines with a gateway/jump host to the generated ssh_config file"
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
   default = "pd-ssd"
}

variable "pmm_type" {
  default = "e2-standard-2"
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
  storage_endpoint = "https://storage.googleapis.com"
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
    northamerica-northeast1 = "projects/centos-cloud/global/images/centos-stream-9-v20231115"
    #northamerica-northeast1 = "ubuntu-2404-noble-amd64-v20250527"
  }
}

# Save money by running spot instances but they may be terminated by google at any time
variable "use_spot_instances" {
  type = bool
  default = false
}

variable "data_disk_type" {
  default = "pd-standard"
}

#############
# Networking
#############

variable "region" {
  type    = string
  default = "northamerica-northeast1"
}

variable "default_vpc_name" {
  description = "Base VPC name"
  type        = string
  default     = "mongo"
}

locals {
  vpc = "${var.prefix}-${var.default_vpc_name}"
}

variable "subnet_name" {
  type = string
  default = "mongo-subnet"
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