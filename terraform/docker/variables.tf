################
# Project/access
################

variable "env_tag" {
  default = "test"
  description = "Name of Environment. Replace these with your own custom name to avoid collisions with existing containers"
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
  default = "2"
  description = "Number of mongos to provision"
}

######################
# Security Credentials 
######################

variable "keyfile" {
  default = "KYYVuRIooX+S2Ee6GDUpYiI6rpx879XYYwWD44tF/WtogW0o8Z4Ua0/Fs+Nez4GO"
  description = "Content of the keyfile for MongoDB replicaset member authentication"
}

variable "keyfile_path" {
  default = "/etc/mongo/mongodb-keyfile.key"
  description = "Path to the keyfile on MongoDB containers"
}

variable "mongodb_root_user" {
  default = "root"
  description = "MongoDB user to be created with root perms"  
}

variable "mongodb_root_password" {
  default = "percona"
  description = "MongoDB root user password"  
}

################
# Shards
################

variable "shardsvr_tag" {
  description = "Name of the shard servers"
  default = "shard"
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
  default = "cfg"
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
  default = "mongos"
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
  default = "arb"
}

variable "arbiter_port" {
  description = "Port of the arbiter servers"
  default = "27018"
}

#############
# PMM
#############

variable "pmm_tag" {
  description = "Name of the PMM server"
  default = "pmm-server"
}

variable "renderer_tag" {
  description = "Name of the Grafana image renderer container"
  default = "grafana-renderer"
}

variable "pmm_client_container_suffix" {
  default = "pmm-client"
  description = "Suffix for PMM client container"
}

variable "pmm_port" {
  description = "Port of the PMM server inside docker network"
# PMM 3 uses 8443
#  default = "8443"
  default = "443"
}

variable "pmm_external_port" {
  description = "Port of the PMM server as seen from outside docker"
  default = "443"
}

variable "pmm_client_port" {
  description = "Port of the PMM client inside docker network"
  default = "42002"
}

variable "renderer_port" {
  description = "Port of the Grafana renderer"
  default = "8081"
}

variable "pmm_user" {
  description = "Username for PMM web interface and clients"
  default = "admin"
}

variable "pmm_password" {
  description = "Password for PMM web interface and clients"
  default = "admin"
}

variable "mongodb_pmm_user" {
  default = "pmm"
  description = "MongoDB user to be created with for PBM"  
}

variable "mongodb_pmm_password" {
  default = "percona"
  description = "MongoDB PBM user password"  
}

variable "cluster" {
  description = "Name of the cluster as seen on PMM server"
  default = "docker-test"
}

#############
# YCSB
#############

variable "ycsb_container_suffix" {
  default = "ycsb"
  description = "Suffix for YCSB container"
}


#############
# PBM
#############

variable "pbm_container_suffix" {
  default = "pbm-agent"
  description = "Suffix for PBM agent containers. Will be appended to each cluster component"
}

variable "pbm_cli_container_suffix" {
  default = "pbm-cli"
  description = "Suffix for PBM CLI container"
}

variable "mongodb_pbm_user" {
  default = "pbmuser"
  description = "MongoDB user to be created with for PBM"  
}

variable "mongodb_pbm_password" {
  default = "percona"
  description = "MongoDB PBM user password"  
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

###############
# Docker Images
###############

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
  #default = "perconalab/pmm-server:3-dev-latest"  
  default = "percona/pmm-server:2"
}

variable "pmm_client_image" {
  description = "Docker image for PMM client"
  default = "percona/pmm-client:2"
  #default = "perconalab/pmm-client:3-dev-latest"
}

variable "renderer_image" {
  description = "Docker image for Grafana renderer container"
  default = "grafana/grafana-image-renderer:latest"
}

variable "base_os_image" {
  description = "Base OS image for the custom Docker image created with pbm-agent and mongod. Required for physical restores"
  #default = "quay.io/centos/centos:stream9"
  #default = "oraclelinux:8"
  default = "redhat/ubi9-minimal"
  #default = "redhat/ubi9"
}

variable "ycsb_os_image" {
  description = "Base OS image for the custom Docker image created with YCSB"
  default = "redhat/ubi8"
}

variable "custom_image" {
  description = "Name of the local Docker image to be created for pbm-agent + current mongod version. Required for physical restores"
  default = "percona-backup-mongodb-agent-custom"
}

variable "ycsb_image" {
  description = "Name of the local Docker image to be created for YCSB benchmark"
  default = "ycsb"
}

variable "minio_image" {
  description = "Minio Docker image"
  default = "minio/minio"
}

variable "uid" {
  description = "The user id under which the main process runs in the container created for pbm-agent + current mongod version"
  default = 1001
}

#############
# Networking
#############

variable "network_name" {
  type    = string
  default = "mongo-terraform"
}
