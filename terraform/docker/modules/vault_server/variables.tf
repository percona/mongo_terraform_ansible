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

variable "pki_certs_volume_name" {
  description = "Name of the Docker volume shared with other containers (Keycloak, MongoDB) for PKI certificates"
  default     = "vault-pki-certs"
  type        = string
}

variable "keycloak_common_name" {
  description = "Hostname of the Keycloak container, used as the Common Name and SAN in the issued TLS certificate"
  default     = "keycloak"
  type        = string
}

variable "vault_keycloak_role" {
  description = "Vault PKI role name used to issue the Keycloak TLS certificate"
  default     = "keycloak"
  type        = string
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

