######
# LDAP
######

variable "ldap_server" {
  default = "ldap"
  type = string
}

variable "ldap_port" {
  default = 389
  type = number
}

variable "ldap_image" {
  description = "LDAP Docker image"
  default = "osixia/openldap:1.5.0"
  type = string
}

variable "ldap_admin_server" {
  default = "phpldapadmin"
  type = string
}

variable "ldap_admin_port" {
  default = 80
  type = number
}

variable "ldap_external_admin_port" {
  default = 8080
  type = number
}

variable "ldap_admin_image" {
  description = "LDAP Admin Docker image"
  default = "osixia/phpldapadmin:0.9.0"
  type = string
}

variable "domain_name" {
  description = "Name of the DNS domain"
  default = ""
}

variable "env_tag" {
  description = "Name of the Environment"
  default = "test"
}

variable "enable_ldap" {
  type        = bool
  description = "Enable LDAP authentication"
  default     = false
}

variable "ldap_uri" {
  type        = string
  description = "URI of the LDAP server"
  default     = "ldap://ldap:389"
}

variable "ldap_bind_dn" {
  type        = string
  description = "LDAP bind DN for authentication"
  default     = "cn=admin,dc=example,dc=org"
}

variable "ldap_bind_pw" {
  type        = string
  description = "LDAP bind password"
  default     = "admin"
}

variable "ldap_user_search_base" {
  type        = string
  description = "Base DN used for user search in LDAP"
  default     = "ou=users,dc=example,dc=org"
}

variable "ldap_domain" {
  default = "example.org"
}

variable "ldap_org" {
  default = "Example Org"
}

# Admin user is cn=admin,dc=example,dc=org
variable "ldap_admin_password" {
  default = "admin"
  type = string
}

variable "ldap_users" {
  default = [
    {
      uid      = "alice"
      cn       = "Alice"
      sn       = "Admin"
      password = "secret123"
    }
  ]
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