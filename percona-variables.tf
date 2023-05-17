variable "env_tag" {
  description = "Name of Environment"
  default = "dev"
}

variable "configsvr_type" {
	default = "e2-small"
	description = "instance type of the config server"
}

variable "configsvr_count" {
  default = "3"
	description = "Number of config servers to be used"
}

variable "configsvr_volume_size" {
	default = "100"
	description = "storage size for the config server"
}

variable "shardsvr_type" {
	default = "e2-small"
	description = "instance type of the shard server"
}

variable "shard_count" {
  default = "2"
  description = "Number of shards to be used"
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
	default = "e2-micro"
	description = "instance type of the mongos servers"
}

variable "mongos_count" {
  default = "1"
	description = "Number of mongos to provision"
}

variable "data_disk_type" {
  default = "pd-standard"
}

variable "pmm_type" {
	default = "e2-standard-2"
	description = "instance type of the PMM server"
}

variable "pmm_volume_size" {
	default = "100"
	description = "storage size for the PMM server"
}

variable "centos_amis" {
  description = "CentOS AMIs by region"
  default = {
    northamerica-northeast1 = "centos-7-v20230509"
  }
}

