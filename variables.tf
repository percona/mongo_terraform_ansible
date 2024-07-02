# replace these with your own
variable "project_id" {
  type    = string
  default = "gs-techleads"
}

# replace these with your own to avoid collisions
variable "env_tag" {
  description = "Name of Environment"
  default = "igtest"
}

variable "gce_ssh_users" {
  description = "SSH user names, and their public key files to be added to authorized_keys"
  default = {
    ivan_groenewold = "ivan.pub"
#    ,user2 = "user2.pub"
  }
}

# This one is only used to auto-generate an ssh_config file. Each person running this code should set it to its own SSH user name
variable "my_ssh_user" {
  default = "ivan_groenewold"
}

# This affects the SSH config file generated adding a proxycommand with a gateway host
variable "enable_ssh_gateway" {
  type = bool
  default = false
}

# Save money by running spot instances but they may be terminated by google at any time
variable "use_spot_instances" {
  type = bool
  default = false
}

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

variable "configsvr_tag" {
  description = "Name of the config servers"
  default = "mongodb-cfg"
}

variable "shard_tag" {
  description = "Name of the shard servers"
  default = "mongodb-shard"
}

variable "mongos_tag" {
  description = "Name of the mongos router servers"
  default = "mongodb-mongos"
}

variable "configsvr_type" {
  default = "e2-medium"
  description = "instance type of the config server"
}

variable "configsvr_count" {
  default = "3"
  description = "Number of config servers to be used"
}

variable "configsvr_ports" {
  type = list(number)
  default = [ 22, 27019 ]
}

variable "configsvr_volume_size" {
  default = "100"
  description = "storage size for the config server"
}

variable "shardsvr_type" {
  default = "e2-medium"
  description = "instance type of the shard server"
}

variable "shard_count" {
  default = "2"
  description = "Number of shards to be used"
}

variable "shard_ports" {
  type = list(number)
  default = [ 22, 27018 ]
}

variable "shardsvr_replicas" {
  default = "3"
  description = "How many replicas per shard"
}

variable "shardsvr_volume_size" {
  default = "100"
  description = "storage size for the shard server"
}

variable "mongos_type" {
  default = "e2-medium"
  description = "instance type of the mongos servers"
}

variable "mongos_count" {
  default = "1"
  description = "Number of mongos to provision"
}

variable "mongos_ports" {
  type = list(number)
  default = [ 22, 27017 ]
}

variable "data_disk_type" {
  default = "pd-standard"
}

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

variable "backup_retention" {
  default = "7"
  description = "days to keep backups in bucket"
}

variable "image" {
  description = "Available images by region"
  default = {
    northamerica-northeast1 = "projects/centos-cloud/global/images/centos-stream-9-v20231115"
  }
}
