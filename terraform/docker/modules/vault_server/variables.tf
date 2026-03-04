# Vault Configuration
variable "vault_image" {
  default = "hashicorp/vault:latest"
}

variable "vault_data_volume" {
  default = "vault_data"
}

variable "vault_container_name" {
  default = "vault"
}

variable "vault_port" {
  default = 8200
}

variable "vault_token" {
  default = "root"
  sensitive = true
}

variable "vault_kv_path_prefix" {
  default = "kv"
}

variable "vault_kv_path" {
  default = "kv/mongo-key"
}

#############
# Networking
#############

variable "network_name" {
  type    = string
  default = "mongo-terraform"
}

variable "bind_to_localhost" {
  type        = bool
  default     = true
  description = "Bind container ports to localhost (127.0.0.1) if true, otherwise to 0.0.0.0"
}

