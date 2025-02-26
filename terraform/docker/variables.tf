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

variable "renderer_image" {
  description = "Docker image for Grafana renderer container"
  default = "grafana/grafana-image-renderer:latest"
}

variable "minio_image" {
  description = "Minio Docker image"
  default = "minio/minio"
}

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
  default = "percona/pmm-server:3"
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
# Networking
#############

variable "network_name" {
  type    = string
  default = "mongo-terraform"
}
