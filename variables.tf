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

# username that will login via SSH to manage the instances, corresponding to the key below
variable "gce_ssh_user" {
  type    = string
  default = "ivan_groenewold"
}

# path your public key file on the machine you are running terraform from
# you will login to the created instances using the private part of this key
variable "gce_ssh_pub_key_file" {
  type    = string
  default = "ivan.pub"
}
