###########
# Keycloak
###########

variable "keycloak_server" {
  default = "keycloak"
  type    = string
}

variable "keycloak_port" {
  default = 8080
  type    = number
}

variable "keycloak_https_port" {
  default     = 8443
  type        = number
  description = "HTTPS port for Keycloak (used for OIDC issuer URL)"
}

variable "pki_certs_volume_name" {
  description = "Name of the Docker volume (created by the vault module) containing the PKI CA cert, Keycloak TLS cert, and Keycloak TLS key"
  default     = "vault-pki-certs"
  type        = string
}

variable "vault_container_name" {
  description = "Name of the Vault container that writes certs to pki_certs_volume_name. When set, an explicit check ensures certs are present before Keycloak starts."
  default     = ""
  type        = string
  validation {
    condition     = var.vault_container_name == "" || can(regex("^[a-zA-Z0-9][a-zA-Z0-9_.-]*$", var.vault_container_name))
    error_message = "vault_container_name must be empty or a valid Docker container name (alphanumeric, hyphens, underscores, and periods only)."
  }
}

variable "keycloak_external_port" {
  default = 8080
  type    = number
}

variable "keycloak_image" {
  description = "Keycloak Docker image"
  default     = "quay.io/keycloak/keycloak:latest"
  type        = string
}

variable "domain_name" {
  description = "Name of the DNS domain"
  default     = ""
}

variable "env_tag" {
  description = "Name of the Environment"
  default     = "test"
}

variable "keycloak_admin_user" {
  description = "Keycloak admin username"
  default     = "admin"
  type        = string
}

variable "keycloak_admin_password" {
  description = "Keycloak admin password"
  default     = "admin"
  type        = string
  sensitive   = true
}

variable "oidc_realm" {
  description = "Name of the Keycloak realm to create for MongoDB OIDC"
  default     = "percona"
  type        = string
}

variable "oidc_client_id" {
  description = "OIDC client ID for MongoDB"
  default     = "mongodb"
  type        = string
}

variable "oidc_client_secret" {
  description = "OIDC client secret for MongoDB"
  default     = "mongodb-secret"
  type        = string
  sensitive   = true
}

variable "oidc_users" {
  description = "List of OIDC users to create in Keycloak"
  default     = []
  type = list(object({
    username   = string
    password   = string
    email      = string
    first_name = string
    last_name  = string
  }))
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
