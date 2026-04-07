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
  default   = "root"
  sensitive = true
}

variable "vault_addr" {
  default = "http://localhost:8200"
}

variable "vault_pki_common_name" {
  default = "vault.local"
}

variable "vault_cert_domain" {
  default = "mongo.local"
}

variable "vault_kv_path_prefix" {
  default = "kv"
}

variable "vault_kv_path" {
  default = "kv/mongo-key"
}

variable "vault_pki_role" {
  default = "mongo"
}

