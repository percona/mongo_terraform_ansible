#############
# Minio
#############

variable "minio_server" {
  default = "minio"
  type = string
}

variable "domain_name" {
  description = "Name of the DNS domain"
  default = "tp.int.percona.com"
}

variable "env_tag" {
  description = "Name of the Environment"
  default = "test"
}

variable "minio_region" {
  description = "Default MINIO region"
  default     = "us-east-1"
  type = string
}

variable "minio_access_key" {
  default = "minio"
  type = string
  sensitive   = true
}

variable "minio_port" {
  default = "9000"
  type = string
}

variable "minio_console_port" {
  default = "9001"
  type = string
}

variable "minio_secret_key" {
  default = "minioadmin"
  type = string
  sensitive   = true
}

variable "bucket_name" {
  default = "mongo-backups"
  description = "S3-compatible storage to put backups"
  type = string
 }

variable "backup_retention" {
  default = "2"
  description = "days to keep backups in bucket"
  type = string
}

###############
# Docker Images
###############

variable "minio_image" {
  description = "Minio Docker image"
  default = "minio/minio"
  type = string
}

#############
# Networking
#############

variable "network_name" {
  type    = string
  default = "mongo-terraform"
}

variable "bind_to_localhost" {
  type = bool
  default = true 
  description = "Bind container ports to localhost (127.0.0.1) if true, otherwise to 0.0.0.0"
}