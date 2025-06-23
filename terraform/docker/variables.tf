################
# Project
################

# By default we deploy 1 sharded cluster, named test01. The configuration can be customized by adding any of the optional values listed below.

variable "clusters" {
  description = "MongoDB clusters to deploy"
  type = map(object({
    env_tag               = optional(string, "test")                # Name of the environment for the cluster
    configsvr_count       = optional(number, 3)                     # Number of config servers to be used
    shard_count           = optional(number, 2)                     # Number of shards to be created
    shardsvr_replicas     = optional(number, 2)                     # How many data-bearing nodes for each shard's replica set
    arbiters_per_replset  = optional(number, 1)                     # Number of arbiters for each shard's replica set
    mongos_count          = optional(number, 2)                     # Number of mongos routers to provision
    bind_to_localhost     = optional(bool, true)                    # Bind container ports to localhost (127.0.0.1) if true, otherwise to 0.0.0.0
  }))

  default = {
    cl01 = {
      env_tag = "test"
    }
#    cl02 = {
#      env_tag = "prod"
#      mongos_count = 1
#   }
  }
}

# By default, no replica sets are provisioned (except those needed for each shard of the sharded clusters).
# If you want to provision separate replica sets, change the default value of replsets below.

variable "replsets" {
   description = "MongoDB replica sets to deploy"
   type = map(object({
    env_tag                   = optional(string, "test")               # Name of the environment for the replica set
    data_nodes_per_replset    = optional(number, 2)                    # Number of data bearing members for the replica set
    arbiters_per_replset      = optional(number, 1)                    # Number of arbiters for the replica set
    bind_to_localhost         = optional(bool, true)                   # Bind container ports to localhost (127.0.0.1) if true, otherwise to 0.0.0.0     
   })) 

   default = {
#     rs01 = {
#       env_tag = "test"
#     }
#     rs02 = {
#       env_tag = "prod"
#     }
   }
}

#############
# PMM
#############

variable "pmm_server_user" {
  description = "Name of the PMM server admin user"
  default = "admin"
  type = string
}

variable "pmm_server_pwd" {
  description = "Password of the PMM server admin user"
  default = "admin"
  type = string
  sensitive   = true
}

variable "pmm_host" {
  description = "Name of the PMM server"
  default = "pmm-server"
  type = string
}

variable "renderer_tag" {
  description = "Name of the Grafana image renderer container"
  default = "grafana-renderer"
  type = string  
}

variable "watchtower_tag" {
  description = "Name of the Watchtower container"
  default = "watchtower"
  type = string  
}

variable "pmm_port" {
  description = "Port of the PMM server inside docker network"
  # PMM 3 uses 8443. PMM 2 uses 443
  # default = "443"
  default = "8443"
  type = string
}

variable "pmm_external_port" {
  description = "Port of the PMM server as seen from outside docker"
  default = "8443"
  type = string
}

variable "renderer_port" {
  description = "Port of the Grafana renderer"
  default = "8081"
  type = string
}

variable "watchtower_port" {
  description = "Port of the Watchtower"
  default = "8080"
  type = string
}

variable "watchtower_token" {
  description = "Watchtower API token"
  default = "1234567890"
  type = string
}

#############
# Bucket
#############

variable "minio_region" {
  description = "Default MINIO region"
  default     = "us-east-1"
  type = string
}

variable "minio_access_key" {
  default = "minio"
  type = string
  sensitive   = true
}

variable "minio_server" {
  default = "minio"
  type = string
}

variable "minio_port" {
  default = "9000"
  type = string
}

variable "minio_console_port" {
  default = "9001"
  type = string
}

variable "minio_secret_key" {
  default = "minioadmin"
  type = string
  sensitive   = true
}

variable "bucket_name" {
  default = "mongo-backups"
  description = "S3-compatible storage to put backups"
  type = string
 }

variable "backup_retention" {
  default = "2"
  description = "days to keep backups in bucket"
  type = string
}

###############
# Docker Images
###############

variable "base_os_image" {
  description = "Base OS image for the custom Docker image created with pbm-agent and mongod. Required for physical restores"
  #default = "quay.io/centos/centos:stream9"
  #default = "oraclelinux:8"
  default = "redhat/ubi9-minimal"
  #default = "redhat/ubi9"
}

variable "psmdb_image" {
  description = "Docker image for MongoDB"
  default = "percona/percona-server-mongodb:latest"
}

variable "pbm_image" {
  description = "Docker image for PBM"
  default = "percona/percona-backup-mongodb:latest"
}

variable "pbm_mongod_image" {
  description = "Name of the local Docker image to be created for pbm-agent + current mongod version. Required for physical restores"
  default = "percona/pbm-agent"
}

variable "renderer_image" {
  description = "Docker image for Grafana renderer container"
  default = "grafana/grafana-image-renderer:latest"
  type = string
}

variable "watchtower_image" {
  description = "Docker image for Watchtower container"
  default = "percona/watchtower:latest"
  type = string
}

variable "minio_image" {
  description = "Minio Docker image"
  default = "minio/minio"
  type = string
}

variable "pmm_server_image" {
  description = "Docker image for PMM server"
  #default = "perconalab/pmm-server:3-dev-latest"
  #default = "percona/pmm-server:3.0"
  default = "percona/pmm-server:latest"
  type = string
}

variable "pmm_client_image" {
  description = "Docker image for PMM client"
  default = "percona/pmm-client:latest"
  #default = "perconalab/pmm-client:3-dev-latest"
}

variable "docker_socket" {
  description = "Location of the socket file for docker"
  default = "/var/run/docker.sock"
  type = string
}

#############
# YCSB
#############

variable "ycsb_container_suffix" {
  default = "ycsb"
  description = "Suffix for YCSB container"
}

variable "ycsb_os_image" {
  description = "Base OS image for the custom Docker image created with YCSB"
  default = "redhat/ubi8-minimal"
}

variable "ycsb_image" {
  description = "Name of the local Docker image to be created for YCSB benchmark"
  default = "percona/ycsb"
}

#############
# Networking
#############

variable "network_name" {
  type    = string
  default = "mongo-terraform"
}

variable "bind_to_localhost" {
  type = bool
  default = true 
  description = "Bind container ports to localhost (127.0.0.1) if true, otherwise to 0.0.0.0"
}
