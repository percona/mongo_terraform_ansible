variable "env_tag" {
  description = "Name of Environment"
  default = "igtest"
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
  default = "1"
  description = "Number of shards to be used"
}

variable "shard_ports" {
  type = list(number)
  default = [ 22, 27018 ]
}

variable "shardsvr_replicas" {
  default = "5"
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

