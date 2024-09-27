################
# Project/access
################

variable "env_tag" {
  default = "aws-test"
  description = "Name of Environment. Replace these with your own custom name to avoid collisions"
}

variable "ssh_public_key_path" {
  description = "SSH public key file to be added to authorized_keys"
  default =  "ivan.pub"
}

variable "my_ssh_user" {
  default = "ec2-user"
  description = "Used to auto-generate the ssh_config file. Each person running this code should set it to its own SSH user name"  
}

variable "enable_ssh_gateway" {
  type = bool
  default = false
  description = "Adds proxycommand lines with a gateway/jump host to the generated ssh_config file"
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
  default = "1"
  description = "Number of mongos to provision"
}

################
# Shards
################

variable "shard_tag" {
  description = "Name of the shard servers"
  default = "mongodb-shard"
}

variable "shardsvr_type" {
  default = "t2-medium"
  description = "instance type of the shard server"
}

variable "shardsvr_volume_size" {
  default = "50"
  description = "storage size for the shard server"
}

variable "shard_ports" {
  type = list(number)
  default = [ 22, 27018 ]
}

################
# CSRS
################

variable "configsvr_tag" {
  description = "Name of the config servers"
  default = "mongodb-cfg"
}

variable "configsvr_type" {
  default = "t2-medium"
  description = "instance type of the config server"
}

variable "configsvr_volume_size" {
  default = "20"
  description = "storage size for the config server"
}

variable "configsvr_ports" {
  type = list(number)
  default = [ 22, 27019 ]
}

################
# Mongos routers
################

variable "mongos_tag" {
  description = "Name of the mongos router servers"
  default = "mongodb-mongos"
}

variable "mongos_type" {
  default = "t2-medium"
  description = "instance type of the mongos servers"
}

variable "mongos_ports" {
  type = list(number)
  default = [ 22, 27017 ]
}

#############
# Arbiters
#############

variable "arbiter_tag" {
  description = "Name of the arbiter servers"
  default = "mongodb-arb"
}

variable "arbiter_type" {
  default = "t2-medium"
  description = "instance type of the arbiter server"
}

variable "arbiter_ports" {
  type = list(number)
  default = [ 22, 27018 ]
}

#############
# PMM
#############

variable "pmm_tag" {
  description = "Name of the PMM server"
  default = "percona-pmm"
}

variable "pmm_disk_type" {
   default = "gp2"
}

variable "pmm_type" {
  default = "t2-large"
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

#############
# Bucket
#############

variable bucket_name { 
  default = "mongo-backups"
  description = "S3-compatible storage to put backups"
 }

variable "backup_retention" {
  default = "2"
  description = "days to keep backups in bucket"
}

#############
# Instances
#############

variable "image" {
  description = "Available images by region"
  default = {
    us-west-2 = "ami-0ad8bfd4b10994785"
  }
}

# Save money by running spot instances but they may be terminated by AWS at any time
variable "use_spot_instances" {
  type = bool
  default = false
}

variable "data_disk_type" {
  default = "gp2"
}

#############
# Networking
#############

variable "region" {
  type    = string
  default = "us-west-2"
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

variable "subnet_count" {
  default = 3
}