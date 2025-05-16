################
# Project
################

variable "project_id" {
  type    = string
  default = "gs-techleads"
  description = "GCP project name. Replace with the project your GCP account belongs to"
}

variable "rs_name" {
  description = "Name of the MongoDB cluster"
  default = "rs01"
}

variable "env_tag" {
  default = "qa"
  description = "Name of Environment. Replace these with your own custom name to avoid collisions"
}

variable "gce_ssh_users" {
  description = "SSH user names, and their public key files to be added to authorized_keys"
  default = {
    ivan_groenewold = "ivan.pub"
#    ,user2 = "user2.pub"
  }
}

variable "my_ssh_user" {
  default = "ivan_groenewold"
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

variable "data_nodes_per_replset" {
  default = "2"
  description = "How many data bearing nodes per replset"
}

variable "arbiters_per_replset" {
  default = "1"
  description = "Number of arbiters per replica set"
}

######################
# Data bearing members
######################

variable "replset_tag" {
  description = "Name of the replicaset servers"
  default = "svr"
}

variable "replsetsvr_ports" {
  type = list(number)
  default = [ 27017 ]
}

variable "replsetsvr_volume_size" {
  default = "1000"
  description = "storage size for the replica set servers"
}

variable "replsetsvr_type" {
  default = "e2-medium"
  description = "instance type of the replica set servers"
}

#############
# Arbiters
#############

variable "arbiter_tag" {
  description = "Name of the arbiter servers"
  default = "mongodb-arb"
}

variable "arbiter_type" {
  default = "e2-medium"
  description = "instance type of the arbiter server"
}

variable "arbiter_ports" {
  type = list(number)
  default = [ 27017 ]
}

#############
# Instances
#############

variable "image" {
  description = "Available images by region"
  default = {
    northamerica-northeast1 = "projects/centos-cloud/global/images/centos-stream-9-v20231115"
  }
}

# Save money by running spot instances but they may be terminated by google at any time
variable "use_spot_instances" {
  type = bool
  default = false
}

variable "data_disk_type" {
  default = "pd-standard"
}

#############
# Networking
#############

variable "region" {
  type    = string
  default = "northamerica-northeast1"
}

variable "vpc" {
  type    = string
  default = "mongo-terraform"
}

variable "subnet_name" {
  type = string
  default = "mongo-subnet"
}

variable "subnet_cidr" {
  type    = string
  default = "10.128.0.0/20"
}