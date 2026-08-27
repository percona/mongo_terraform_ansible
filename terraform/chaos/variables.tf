################
# Project
################

variable "prefix" {
  type        = string
  default     = "ig"
  description = "Prefix to be applied to the resources created, make sure to change it to avoid collisions with other users projects"
}

# By default we deploy 1 sharded cluster, named ig-cl01. Make sure to change the default name and prefix (ig-cl01) to avoid duplicates. The configuration can be customized by adding the optional values listed.
variable "clusters" {
  description = "MongoDB clusters to deploy"
  type = map(object({
    env_tag              = optional(string, "test") # Name of Environment for the cluster
    configsvr_count      = optional(number, 3)      # Number of config servers to be used
    shard_count          = optional(number, 2)      # Number of shards to be used
    shardsvr_replicas    = optional(number, 2)      # How many data bearing nodes per shard
    arbiters_per_replset = optional(number, 1)      # Number of arbiters per replica set
    mongos_count         = optional(number, 2)      # Number of mongos to provision
    enable_audit         = optional(bool, false)    # Enable audit logging
    use_tls              = optional(bool, false)    # Use TLS for this cluster
    audit_filter         = optional(string, "")     # Optional audit filter override
    mongodb_distribution = optional(string, "")
    mongo_release        = optional(string, "")
    mongo_version        = optional(string, "")
    mongo_repo           = optional(string, "")
    pbm_version          = optional(string, "")
    pbm_repo             = optional(string, "")
    pmm_client_version   = optional(string, "")
    pmm_client_repo      = optional(string, "")
    enable_pmm           = optional(bool, true)
    enable_pbm           = optional(bool, true)
    enable_mongot        = optional(bool, false)
    mongot_source        = optional(string, "")
    mongot_repo          = optional(string, "")
    mongot_version       = optional(string, "")
    os_image             = optional(string, "")
    ldap_server          = optional(string, "")
  }))

  default = {
    ig-cl01 = {
      env_tag = "test"
    }
    #    ig-cl02 = {
    #      env_tag = "prod"
    #      mongos_count = 1
    #    }
  }
}

# By default, no replica sets are deployed (except those needed for the sharded clusters).
# If you want to provision separate replica sets, uncomment the default below. Make sure to change the default name and prefix (ig-rs01) to avoid duplicates.
variable "replsets" {
  description = "MongoDB replica sets to deploy"
  type = map(object({
    env_tag                = optional(string, "test") # Name of Environment
    data_nodes_per_replset = optional(number, 2)      # Number of data bearing members per replset
    arbiters_per_replset   = optional(number, 1)      # Number of arbiters per replica set
    enable_audit           = optional(bool, false)    # Enable audit logging
    use_tls                = optional(bool, false)    # Use TLS for this replica set
    audit_filter           = optional(string, "")     # Optional audit filter override
    mongodb_distribution   = optional(string, "")
    mongo_release          = optional(string, "")
    mongo_version          = optional(string, "")
    mongo_repo             = optional(string, "")
    pbm_version            = optional(string, "")
    pbm_repo               = optional(string, "")
    pmm_client_version     = optional(string, "")
    pmm_client_repo        = optional(string, "")
    enable_pmm             = optional(bool, true)
    enable_pbm             = optional(bool, true)
    enable_mongot          = optional(bool, false)
    mongot_source          = optional(string, "")
    mongot_repo            = optional(string, "")
    mongot_version         = optional(string, "")
    os_image               = optional(string, "")
    ldap_server            = optional(string, "")
  }))

  default = {
    #    ig-rs01 = {
    #      env_tag = "test"
    #    }
    #    ig-rs02 = {
    #      env_tag = "prod"
    #    }
  }
}

variable "ldap_servers" {
  description = "LDAP servers to deploy. MongoDB clusters and replica sets select one with ldap_server."
  type = map(object({
    domain         = optional(string, "example.com")
    organization   = optional(string, "Example Inc")
    admin_password = optional(string, "admin")
    cpu_cores      = optional(number, 2)
    memory_gb      = optional(number, 4)
    users          = optional(list(object({ uid = string, cn = string, sn = string, password = string })), [])
    mongodb_users  = optional(list(object({ user = string, roles = list(string) })), [])
  }))
  default = {}
}


variable "my_ssh_user" {
  default     = "your_ssh_username"
  description = "Used to auto-generate the ssh_config file. Each person running this code should set it to its own SSH user name"
}

variable "ssh_private_key_path" {
  description = "Optional SSH private key file used by generated Ansible inventory and ssh_config. Empty uses ssh-agent/default SSH behavior."
  type        = string
  default     = ""
}

variable "enable_ssh_gateway" {
  type        = bool
  default     = false
  description = "Adds proxycommand lines with a gateway/jump host to the generated ssh_config file"
}

variable "ssh_gateway_name" {
  type        = string
  default     = "gateway"
  description = "Name of your jump host to use for ssh_config"
}

variable "port_to_forward" {
  type        = string
  default     = "23443"
  description = "Local port number to forward via SSH to access PMM UI over localhost"
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

variable "pmm_cpu_cores" {
  default     = 4
  description = "Number of CPU cores for the PMM server instance"
}

variable "pmm_memory_gb" {
  default     = 8
  description = "Memory in GB for the PMM server instance"
}

variable "pmm_volume_size" {
  default     = 20
  description = "Root disk size in GB for the PMM server"
}

variable "pmm_port" {
  type    = number
  default = 8443
}

variable "pmm_image" {
  type        = string
  default     = "docker.io/percona/pmm-server:latest"
  description = "Docker image used by Ansible to run the PMM server container."
}

variable "enable_pmm" {
  type        = bool
  default     = true
  description = "Deploy a PMM monitoring server. Set to false to skip PMM entirely."
}

#############
# TLS CA
#############

variable "enable_ca" {
  type        = bool
  default     = false
  description = "Provision a certificate authority host and add it to generated inventories."
}

variable "ca_placement" {
  type        = string
  default     = "dedicated"
  description = "Place the TLS certificate authority on a dedicated VM or the PMM host."

  validation {
    condition     = contains(["dedicated", "pmm"], var.ca_placement)
    error_message = "ca_placement must be either dedicated or pmm."
  }

  validation {
    condition     = !var.enable_ca || var.ca_placement != "pmm" || var.enable_pmm
    error_message = "enable_pmm must be true when CA provisioning is enabled with ca_placement set to pmm."
  }
}

variable "default_ca_host" {
  type        = string
  default     = "ca-server"
  description = "Base hostname for the dedicated CA VM."
}

locals {
  ca_host = "${var.prefix}-${var.default_ca_host}"
}

variable "ca_cpu_cores" {
  type        = number
  default     = 2
  description = "Number of CPU cores for the dedicated CA instance."

  validation {
    condition     = contains([2, 4, 8, 16, 32], var.ca_cpu_cores)
    error_message = "ca_cpu_cores must be one of 2, 4, 8, 16, or 32."
  }
}

variable "ca_memory_gb" {
  type        = number
  default     = 4
  description = "Memory in GB for the dedicated CA instance."

  validation {
    condition     = contains([4, 8, 16], var.ca_memory_gb)
    error_message = "ca_memory_gb must be one of 4, 8, or 16."
  }
}

variable "ca_volume_size" {
  type        = number
  default     = 20
  description = "Root disk size in GB for the dedicated CA instance."

  validation {
    condition     = contains([20, 40, 60, 80, 100], var.ca_volume_size)
    error_message = "ca_volume_size must be one of 20, 40, 60, 80, or 100."
  }
}

variable "enable_ycsb" {
  type        = bool
  default     = false
  description = "Deploy a dedicated YCSB workload generator VM."
}

variable "default_ycsb_host" {
  description = "Base YCSB host name"
  type        = string
  default     = "ycsb"
}

locals {
  ycsb_host = "${var.prefix}-${var.default_ycsb_host}"
}

variable "ycsb_cpu_cores" {
  default     = 2
  description = "Number of CPU cores for the YCSB instance"
}

variable "ycsb_memory_gb" {
  default     = 4
  description = "Memory in GB for the YCSB instance"
}

variable "ycsb_volume_size" {
  default     = 20
  description = "Root disk size in GB for the YCSB instance"
}

#############
# Backup (Minio)
#############

variable "default_minio_host" {
  description = "Base Minio host name"
  type        = string
  default     = "minio-server"
}

locals {
  minio_host = "${var.prefix}-${var.default_minio_host}"
}

variable "minio_cpu_cores" {
  default     = 2
  description = "Number of CPU cores for the Minio server instance"
}

variable "minio_memory_gb" {
  default     = 4
  description = "Memory in GB for the Minio server instance"
}

variable "minio_volume_size" {
  default     = 20
  description = "Root disk size in GB for the Minio server (stores all backups)"
}

variable "minio_port" {
  type        = number
  default     = 9000
  description = "Port for the Minio API endpoint"
}

variable "minio_console_port" {
  type        = number
  default     = 9001
  description = "Port for the Minio web console"
}

variable "minio_root_user" {
  type        = string
  default     = "minioadmin"
  description = "Minio root user (access key)"
}

variable "minio_root_password" {
  type        = string
  default     = "minioadmin"
  sensitive   = true
  description = "Minio root password (secret key)"
}

variable "default_bucket_name" {
  description = "Base bucket name for MongoDB backups"
  type        = string
  default     = "mongo-bkp-storage"
}

locals {
  bucket_name = "${var.prefix}-${var.default_bucket_name}"
}

variable "backup_retention" {
  default     = 2
  description = "Days to keep backups in Minio bucket"
}

#############
# Instances
#############

variable "os_image" {
  description = "Operating system for all instances"
  type        = string
  default     = "Ubuntu 24.04"
}

variable "delete_after_days" {
  type        = number
  default     = null
  description = "Number of days before instances are automatically deleted. Null omits the provider argument."
}

################
# Instance sizes
################

variable "shardsvr_cpu_cores" {
  default     = 2
  description = "Number of CPU cores for MongoDB shard server instances"
}

variable "shardsvr_memory_gb" {
  default     = 4
  description = "Memory in GB for MongoDB shard server instances"
}

variable "shardsvr_volume_size" {
  default     = 20
  description = "Root disk size in GB for MongoDB shard server instances"
}

variable "configsvr_cpu_cores" {
  default     = 2
  description = "Number of CPU cores for MongoDB config server instances"
}

variable "configsvr_memory_gb" {
  default     = 4
  description = "Memory in GB for MongoDB config server instances"
}

variable "configsvr_volume_size" {
  default     = 20
  description = "Root disk size in GB for MongoDB config server instances"
}

variable "mongos_cpu_cores" {
  default     = 2
  description = "Number of CPU cores for mongos router instances"
}

variable "mongos_memory_gb" {
  default     = 4
  description = "Memory in GB for mongos router instances"
}

variable "arbiter_cpu_cores" {
  default     = 2
  description = "Number of CPU cores for MongoDB arbiter instances"
}

variable "arbiter_memory_gb" {
  default     = 4
  description = "Memory in GB for MongoDB arbiter instances"
}

variable "replsetsvr_cpu_cores" {
  default     = 2
  description = "Number of CPU cores for standalone replica set data-bearing node instances"
}

variable "replsetsvr_memory_gb" {
  default     = 4
  description = "Memory in GB for standalone replica set data-bearing node instances"
}

variable "replsetsvr_volume_size" {
  default     = 20
  description = "Root disk size in GB for standalone replica set data-bearing node instances"
}

#############
# Networking
#############

# Source IPs that will connect to the cluster from outside the subnet
variable "source_ranges" {
  type        = string
  default     = ""
  description = "CIDR range for firewall rules. Leave empty to create instances with no firewall rules."
}

# Structured per-rule firewall access rules (replaces source_ranges when non-empty).
# Each rule: { source = "CIDR", port = "PORT", protocol = "tcp", comment = "..." }
variable "firewall_rules" {
  type = list(object({
    source   = string
    port     = string
    protocol = string
    comment  = string
  }))
  default     = []
  description = "Custom firewall rules. Each entry specifies a CIDR, port, protocol, and comment."
}

#############
# CHAOS Provider
#############

variable "chaos_api_token" {
  type        = string
  sensitive   = true
  default     = null
  description = "CHAOS API token. If null, the CHAOS_API_TOKEN environment variable is used."
}

variable "enable_minio" {
  type        = bool
  default     = true
  description = "Deploy a Minio S3-compatible backup storage VM. Set to false to skip Minio."
}

#############
# Package Versions
#############

variable "mongo_release" {
  type        = string
  default     = ""
  description = "MongoDB release line (e.g. psmdb-80, 8.0, 8.3). Empty string uses the default from group_vars."
}

variable "mongodb_distribution" {
  type        = string
  default     = ""
  description = "MongoDB distribution for non-Docker packages: psmdb, community, or enterprise. Empty string uses the default from group_vars."
}

variable "mongo_version" {
  type        = string
  default     = ""
  description = "Specific MongoDB version to install (e.g. 8.0.4). Empty string installs the latest available."
}

variable "mongo_repo" {
  type        = string
  default     = ""
  description = "Percona repository channel for MongoDB packages (release, testing, experimental). Empty string uses group_vars default."
}

variable "pbm_release" {
  type        = string
  default     = ""
  description = "Percona release channel for PBM (e.g. pbm). Empty string uses the default from group_vars."
}

variable "mongot_repo" {
  type        = string
  default     = ""
  description = "Percona repository channel for Percona Search packages (release, testing, experimental). Empty string uses group_vars default."
}

variable "pbm_version" {
  type        = string
  default     = ""
  description = "Specific PBM version to install (e.g. 2.4.0). Empty string installs the latest available."
}

variable "pbm_repo" {
  type        = string
  default     = ""
  description = "Percona repository channel for PBM packages (release, testing, experimental). Empty string uses group_vars default."
}

variable "pmm_client_version" {
  type        = string
  default     = ""
  description = "Specific PMM client version to install (e.g. 3.4.0). Empty string installs the latest available."
}

variable "pmm_client_repo" {
  type        = string
  default     = ""
  description = "Percona repository channel for PMM client packages (release, testing, experimental). Empty string uses group_vars default."
}
