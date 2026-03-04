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
  description = "HTTPS port for Keycloak (used for OIDC issuer URL; internal Docker port)"
}

variable "keycloak_https_external_port" {
  default     = 8444
  type        = number
  description = "External HTTPS port for Keycloak exposed on the host. Use a value other than 8443 to avoid conflicts with PMM."
}

variable "pki_certs_volume_name" {
  description = "Name of the Docker volume created by this module to store the Keycloak TLS cert, key, and CA cert. Must match the value used in MongoDB modules so they can trust the Keycloak CA."
  default     = "keycloak-certs"
  type        = string
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
