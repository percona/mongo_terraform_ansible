##################
# Sharded Clusters
##################

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
    pmm_host              = optional(string, "pmm-server")
    pmm_port              = optional(number, 8443)
    pmm_server_user       = optional(string, "admin")
    pmm_server_pwd        = optional(string, "admin")
    minio_server          = optional(string, "minio")
    minio_port            = optional(number, 9000)
    bucket_name           = optional(string, "mongo-backups")
    base_os_image         = optional(string, "redhat/ubi9-minimal")
    psmdb_image           = optional(string, "percona/percona-server-mongodb:latest")
    pbm_image             = optional(string, "percona/percona-backup-mongodb:latest")
    pmm_client_image      = optional(string, "percona/pmm-client:latest")
    network_name          = optional(string, "mongo-terraform")
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

###########################
# Replica Sets (standalone)
###########################

# By default, no replica sets are provisioned (except those needed for each shard of the sharded clusters).
# If you want to provision separate replica sets, change the default value of replsets below.

variable "replsets" {
   description = "MongoDB replica sets to deploy"
   type = map(object({
    env_tag                   = optional(string, "test")               # Name of the environment for the replica set
    data_nodes_per_replset    = optional(number, 2)                    # Number of data bearing members for the replica set
    arbiters_per_replset      = optional(number, 1)                    # Number of arbiters for the replica set
    pmm_host                  = optional(string, "pmm-server")
    pmm_port                  = optional(number, 8443)
    pmm_server_user           = optional(string, "admin")
    pmm_server_pwd            = optional(string, "admin")
    minio_server              = optional(string, "minio")
    minio_port                = optional(number, 9000)
    bucket_name               = optional(string, "mongo-backups")
    base_os_image             = optional(string, "redhat/ubi9-minimal")    
    psmdb_image               = optional(string, "percona/percona-server-mongodb:latest")
    pbm_image                 = optional(string, "percona/percona-backup-mongodb:latest")
    pmm_client_image          = optional(string, "percona/pmm-client:latest")    
    network_name              = optional(string, "mongo-terraform")
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
# PMM Servers
#############

variable "pmm_servers" {
   description = "PMM Servers to deploy"
   type = map(object({
    env_tag                   = optional(string, "test")               # Name of the environment
    pmm_server_image          = optional(string, "percona/pmm-server:latest") 
    pmm_port                  = optional(number, 8443)
    pmm_external_port         = optional(number, 8443)                 # Port of the PMM server as seen from outside docker
    watchtower_token          = optional(string, "1234567890")
    pmm_server_user           = optional(string, "admin")
    pmm_server_pwd            = optional(string, "admin")
    renderer_image            = optional(string, "grafana/grafana-image-renderer:latest")
    watchtower_image          = optional(string, "percona/watchtower:latest")
    network_name              = optional(string, "mongo-terraform")
    bind_to_localhost         = optional(bool, true)                   # Bind container ports to localhost (127.0.0.1) if true, otherwise to 0.0.0.0     
   })) 

   default = {
     pmm-server = {
       env_tag = "test"
     }
#     pmm-server-prod = {
#       env_tag = "prod"
#     }
   }
}

###############
# Minio Servers
###############

variable "minio_servers" {
   description = "Minio Servers to deploy"
   type = map(object({
    env_tag                   = optional(string, "test")               # Name of the environment
    minio_image               = optional(string, "minio/minio")
    minio_port                = optional(number, 9000)
    minio_console_port        = optional(number, 9001)                 
    minio_access_key          = optional(string, "minio")
    minio_secret_key          = optional(string, "minioadmin")
    bucket_name               = optional(string, "mongo-backups")
    backup_retention          = optional(number, 2)                    # Days to keep backups
    network_name              = optional(string, "mongo-terraform")
    bind_to_localhost         = optional(bool, true)                   # Bind container ports to localhost (127.0.0.1) if true, otherwise to 0.0.0.0     
   })) 

   default = {
     minio = {
       env_tag = "test"
     }
#     minio-prod = {
#       env_tag = "prod"
#     }
   }
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