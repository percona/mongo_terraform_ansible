################
# Project/access
################

variable "env_tag" {
  default = "test"
  description = "Name of Environment. Replace these with your own custom name to avoid collisions"
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

variable "keyfile" {
  default = "1234567890"
  description = "Content of the keyfile for member authentication"
}

variable "shardsvr_port" {
  description = "Port of the mongod servers"
  default = "27018"
}

################
# CSRS
################

variable "configsvr_tag" {
  description = "Name of the config servers"
  default = "mongodb-cfg"
}

variable "configsvr_port" {
  description = "Port of the mongod config servers"
  default = "27019"
}

################
# Mongos routers
################

variable "mongos_tag" {
  description = "Name of the mongos router servers"
  default = "mongodb-mongos"
}

variable "mongos_port" {
  description = "Port of the mongos router servers"
  default = "27017"
}

#############
# Arbiters
#############

variable "arbiter_tag" {
  description = "Name of the arbiter servers"
  default = "mongodb-arb"
}


#############
# PMM
#############

variable "pmm_tag" {
  description = "Name of the PMM server"
  default = "percona-pmm"
}

#############
# Bucket
#############

variable "minio_region" {
  description = "Default MINIO region"
  default     = "us-east-1"
}

variable "minio_access_key" {
  default = "minio"
}

variable "minio_server" {
  default = "minio"
}

variable "minio_port" {
  default = "9000"
}

variable "minio_console_port" {
  default = "9001"
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
# Images
#############

variable "psmdb_image" {
  description = "Docker image for MongoDB"
  default = "percona/percona-server-mongodb:latest"
}

variable "pbm_image" {
  description = "Docker image for PBM"
  default = "percona/percona-backup-mongodb:latest"
}

variable "pmm_server_image" {
  description = "Docker image for PMM server"
  default = "percona/pmm-server:2"
}

variable "pmm_client_image" {
  description = "Docker image for PMM client"
  default = "percona/pmm-client:2"
}

variable "base_os_image" {
  description = "Base OS for the custom Docker image with pbm-agent and mongod"
  #default = "quay.io/centos/centos:stream9"
  default = "oraclelinux:8"
}

variable "minio_image" {
  description = "Minio Docker image"
  default = "minio/minio"
}

variable "custom_image" {
  description = "Name of the local Docker image to be created for pbm-agent + mongod. Required for a physical restore"
  default = "pbm-with-mongod"
}

#############
# Networking
#############

variable "network_name" {
  type    = string
  default = "mongo-terraform"
}
=======
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
