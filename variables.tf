################
# Project/access
################

variable "project_id" {
  type    = string
  default = "gs-techleads"
  description = "GCP project name. Replace with the project your GCP account belongs to"
}

variable "env_tag" {
  default = "my-test-env"
  description = "Name of Environment. Replace these with your own custom name to avoid collisions"
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

##################
# MongoDB topology
##################

variable "configsvr_count" {
  default = "3"
  description = "Number of config servers to be used"
}

variable "shard_count" {
  default = "2"
  description = "Number of shards to be used"
}

variable "shardsvr_replicas" {
  default = "3"
  description = "How many data bearing nodes per shard"
}

variable "arbiters_per_replset" {
  default = "0"
  description = "Number of arbiters per replica set"
}

variable "mongos_count" {
  default = "1"
  description = "Number of mongos to provision"
}

################
# Shards
################

variable "shard_tag" {
  description = "Name of the shard servers"
  default = "mongodb-shard"
}

variable "shardsvr_type" {
  default = "e2-medium"
  description = "instance type of the shard server"
}

variable "shardsvr_volume_size" {
  default = "50"
  description = "storage size for the shard server"
}

variable "shard_ports" {
  type = list(number)
  default = [ 22, 27018 ]
}

################
# CSRS
################

variable "configsvr_tag" {
  description = "Name of the config servers"
  default = "mongodb-cfg"
}

variable "configsvr_type" {
  default = "e2-medium"
  description = "instance type of the config server"
}

variable "configsvr_volume_size" {
  default = "20"
  description = "storage size for the config server"
}

variable "configsvr_ports" {
  type = list(number)
  default = [ 22, 27019 ]
}

################
# Mongos routers
################

variable "mongos_tag" {
  description = "Name of the mongos router servers"
  default = "mongodb-mongos"
}

variable "mongos_type" {
  default = "e2-medium"
  description = "instance type of the mongos servers"
}

variable "mongos_ports" {
  type = list(number)
  default = [ 22, 27017 ]
}

#############
# Arbiters
#############

variable "arbiter_tag" {
  description = "Name of the arbiter servers"
  default = "mongodb-arb"
}

variable "arbiter_type" {
  default = "e2-medium"
  description = "instance type of the arbiter server"
}

variable "arbiter_ports" {
  type = list(number)
  default = [ 22, 27018 ]
}

#############
# PMM
#############

variable "pmm_tag" {
  description = "Name of the PMM server"
  default = "percona-pmm"
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

variable "pmm_ports" {
  type = list(number)
  default = [ 22, 443 ]
}

#############
# Bucket
#############

variable bucket_name { 
  default = "mongo-backups"
  description = "S3-compatible storage to put backups"
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

variable "network_name" {
  type    = string
  default = "mongo-terraform"
}

variable "subnet" {
  type    = string
  default = "10.128.0.0/20"
}

variable "subnet_name" {
  type = string
  default = "mongo-subnet"
}
