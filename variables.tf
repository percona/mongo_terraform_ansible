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
  default = "mongo-terraform-test"
}

# user that will login via SSH to manage the instances
variable "gce_ssh_user" {
  type    = string
  default = "ivan_groenewold"
}

variable "gce_ssh_pub_key_file" {
  type    = string
  default = "ivan.pub"
}
