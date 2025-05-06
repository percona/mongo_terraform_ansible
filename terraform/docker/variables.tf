################
# Project
################

# By default we deploy 1 sharded cluster, named test01. The configuration can be customized by adding the optional values listed.

variable "clusters" {
  description = "MongoDB clusters to deploy"
  type = map(object({
    env_tag               = optional(string, "test")                # Name of Environment for the cluster
    configsvr_count       = optional(number, 3)                     # Number of config servers to be used
    shard_count           = optional(number, 2)                     # Number of shards to be used
    shardsvr_replicas     = optional(number, 2)                     # How many data bearing nodes per shard
    arbiters_per_replset  = optional(number, 1)                     # Number of arbiters per replica set
    mongos_count          = optional(number, 2)                     # Number of mongos to provision
    pmm_host              = optional(string, "pmm-server")          # Hostname of PMM server
    pmm_port              = optional(number, 8443)                  # Port of PMM Server
    minio_server          = optional(string, "minio")               # Hostname of Minio server
    minio_port            = optional(number, 9000)                  # Port of Minio Server
  }))

  default = {
    test01 = {
      env_tag = "test"
    }
  }
}

# More sharded clusters can be deployed by appending to the list. 
# The below example provisions another cluster named prod01 with a custom number of mongos in addition to the test01 cluster:
#
# default = {
#   test01 = {
#     env_tag = "test"
#   }
#   prod01 = {
#     env_tag = "prod"
#     mongos_count = 1
#   }
# }

# By default, no replica sets are deployed (except those needed for the sharded clusters).
# If you want to provision separate replica sets, uncomment the code below.

variable "replsets" {
   description = "MongoDB replica sets to deploy"
   type = map(object({
     env_tag                   = optional(string, "test")               # Name of Environment
     data_nodes_per_replset    = optional(number, 2)                    # Number of data bearing members per replset
     arbiters_per_replset      = optional(number, 1)                    # Number of arbiters per replica set
     pmm_host                  = optional(string, "pmm-server")         # Hostname of PMM server
     pmm_port                  = optional(number, 8443)                 # Port of PMM Server
     minio_server              = optional(string, "minio")              # Hostname of Minio server
     minio_port                = optional(number, 9000)                 # Port of Minio Server
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
  default = "443"
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

variable "psmdb_image" {
  description = "Docker image for MongoDB"
  default = "percona/percona-server-mongodb:latest"
  type = string
}

variable "pbm_image" {
  description = "Docker image for PBM"
  default = "percona/percona-backup-mongodb:latest"
  type = string
}

variable "pmm_server_image" {
  description = "Docker image for PMM server"
  #default = "perconalab/pmm-server:3-dev-latest"
  #default = "percona/pmm-server:3.0"
  default = "percona/pmm-server:latest"
  type = string
}

variable "base_os_image" {
  description = "Base OS image for the custom Docker image created with pbm-agent and mongod. Required for physical restores"
  #default = "quay.io/centos/centos:stream9"
  #default = "oraclelinux:8"
  default = "redhat/ubi9-minimal"
  #default = "redhat/ubi9"
  type = string
}

variable "ycsb_os_image" {
  description = "Base OS image for the custom Docker image created with YCSB"
  default = "redhat/ubi8-minimal"
  type = string
}

variable "pbm_mongod_image" {
  description = "Name of the local Docker image to be created for pbm-agent + current mongod version. Required for physical restores"
  default = "percona/pbm-agent-custom"
  type = string
}

variable "ycsb_image" {
  description = "Name of the local Docker image to be created for YCSB benchmark"
  default = "percona/ycsb"
  type = string
}

#############
# Networking
#############

variable "network_name" {
  type    = string
  default = "mongo-terraform"
}
