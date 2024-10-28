################
# Project/access
################

variable "env_tag" {
  default = "docker-test"
  description = "Name of Environment. Replace these with your own custom name to avoid collisions"
}

variable "ssh_users" {
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
  default = "2"
  description = "How many data bearing nodes per shard"
}

variable "arbiters_per_replset" {
  default = "1"
  description = "Number of arbiters per replica set"
}

variable "mongos_count" {
  default = "1"
  description = "Number of mongos to provision"
}

################
# Shards
################

variable "shardsvr_tag" {
  description = "Name of the shard servers"
  default = "mongodb-shard"
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

variable "pmm_ports" {
  type = list(number)
  default = [ 22, 443 ]
}

#############
# Bucket
#############

variable "minio_region" {
  description = "Default MINIO region"
  default     = "us-east-1"
}

variable "minio_server" {
  description = "Default MINIO host and port"
  default     = "localhost:9000"
}

variable "minio_access_key" {
  default = "minio"
}

variable "minio_secret_key" {
  default = "minioadmin"
}

variable "bucket_name" { 
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

variable "docker_image" {
  description = "Docker image"
  default = "quay.io/centos/centos:stream9"
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
