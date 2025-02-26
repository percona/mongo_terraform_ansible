variable "rs_name" {
  description = "Name of the MongoDB replicaset"
  default = "rs01"
}

variable "env_tag" {
  description = "Name of the Environment"
  default = "qa"
}

##################
# MongoDB topology
##################

variable "data_nodes_per_replset" {
  default = "2"
  description = "How many data bearing nodes per replset"
}

variable "arbiters_per_replset" {
  default = "1"
  description = "Number of arbiters per replica set"
}

######################
# Security Credentials
######################

variable "keyfile_contents" {
  default = "KYYVuRIooX+S2Ee6GDUpYiI6rpx879XYYwWD44tF/WtogW0o8Z4Ua0/Fs+Nez4GO"
  description = "Content of the keyfile for MongoDB replicaset member authentication"
}

variable "keyfile_path" {
  default = "/etc/mongo"
  description = "Path to the keyfile on MongoDB containers"
}

variable "keyfile_name" {
  default = "mongodb-keyfile.key"
  description = "Name of the file containing the keyfile on MongoDB containers"
}

variable "mongodb_root_user" {
  default = "root"
  description = "MongoDB user to be created with root perms"
}

variable "mongodb_root_password" {
  default = "percona"
  description = "MongoDB root user password"
}

######################
# Data bearing members
######################

variable "replset_tag" {
  description = "Name of the replicaset servers"
  default = "svr"
}

variable "replset_port" {
  description = "Port of the replset servers"
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
  default = "27017"
}

#############
# PMM
#############

variable "pmm_host" {
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
  # PMM 3 uses 8443. PMM 2 uses 443
  # default = "443"
  default = "8443"
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

variable "pmm_client_image" {
  description = "Docker image for PMM client"
  default = "percona/pmm-client:3"
  #default = "perconalab/pmm-client:3-dev-latest"
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

variable "uid" {
  description = "The user id under which the main process runs in the container created for pbm-agent + current mongod version"
  default = 1001
}

#############
# YCSB
#############

variable "ycsb_container_suffix" {
  default = "ycsb"
  description = "Suffix for YCSB container"
}

#############
# Networking
#############

variable "network_name" {
  type    = string
  default = "mongo-terraform"
}
