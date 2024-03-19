# replace these with your own
variable "project_id" {
  type    = string
  default = "consultants-206215"
}

variable "region" {
  type    = string
  default = "northamerica-northeast1"
}

variable "zone" {
  type    = string
  default = "northamerica-northeast1-a"
}

variable "network_name" {
  type    = string
  default = "mongo-terraform"
}

variable "subnet_name" {
  type = string
  default = "mongo-subnet"
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
