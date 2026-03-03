terraform {
  required_version = ">= 1.0"

  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = ">= 3.6.2"
    }
    minio = {
      source = "aminueza/minio"
    }
  }
}

provider "docker" {}

module "mongodb_clusters" {
  source                  = "./modules/mongodb_cluster"
  for_each                = var.clusters
  cluster_name            = each.key
  domain_name             = each.value.domain_name
  env_tag                 = each.value.env_tag
  configsvr_count         = each.value.configsvr_count
  shard_count             = each.value.shard_count
  shardsvr_replicas       = each.value.shardsvr_replicas
  arbiters_per_replset    = each.value.arbiters_per_replset
  mongos_count            = each.value.mongos_count
  mongodb_root_password   = each.value.mongodb_root_password
  pmm_host                = each.value.pmm_host
  pmm_port                = each.value.pmm_port
  pmm_server_user         = each.value.pmm_server_user
  pmm_server_pwd          = each.value.pmm_server_pwd
  minio_server            = each.value.minio_server
  minio_port              = each.value.minio_port
  base_os_image           = each.value.base_os_image
  psmdb_image             = each.value.psmdb_image
  pbm_image               = each.value.pbm_image
  pmm_client_image        = each.value.pmm_client_image
  network_name            = each.value.network_name
  ldap_servers            = each.value.ldap_servers
  ldap_bind_dn            = each.value.ldap_bind_dn
  ldap_bind_pw            = each.value.ldap_bind_pw
  ldap_user_search_base   = each.value.ldap_user_search_base    
  enable_oidc             = each.value.enable_oidc
  oidc_issuer             = each.value.oidc_issuer
  oidc_audience           = each.value.oidc_audience
  oidc_client_id          = each.value.oidc_client_id
  oidc_auth_name_prefix   = each.value.oidc_auth_name_prefix
  oidc_principal_name     = each.value.oidc_principal_name
  oidc_authorization_claim = each.value.oidc_authorization_claim
  pki_certs_volume_name   = each.value.pki_certs_volume_name
#  enable_tls              = each.value.enable_tls
#  tls_cert_file           = each.value.tls_cert_file
#  tls_key_file            = each.value.tls_key_file
#  tls_ca_file             = each.value.tls_ca_file
#  enable_encryption_rest  = each.value.enable_encryption_rest
#  vault_addr              = each.value.vault_addr
#  vault_token             = each.value.vault_token
#  vault_kv_path           = each.value.vault_kv_path
#  vault_pki_role          = each.value.vault_pki_role  
  bind_to_localhost       = each.value.bind_to_localhost
  enable_pmm              = each.value.enable_pmm
  enable_pbm              = each.value.enable_pbm

  depends_on = [
    module.pmm_server,
    module.minio_server,
    module.ldap_server,
    module.vault_server,
    module.keycloak_server
  ]
}

module "mongodb_replsets" {
  source                  = "./modules/mongodb_replset"
  for_each                = var.replsets
  rs_name                 = each.key
  domain_name             = each.value.domain_name
  env_tag                 = each.value.env_tag
  data_nodes_per_replset  = each.value.data_nodes_per_replset
  arbiters_per_replset    = each.value.arbiters_per_replset
  replset_port            = each.value.replset_port
  arbiter_port            = each.value.arbiter_port
  mongodb_root_password   = each.value.mongodb_root_password  
  pmm_host                = each.value.pmm_host
  pmm_port                = each.value.pmm_port
  pmm_server_user         = each.value.pmm_server_user
  pmm_server_pwd          = each.value.pmm_server_pwd
  minio_server            = each.value.minio_server
  minio_port              = each.value.minio_port
  base_os_image           = each.value.base_os_image  
  psmdb_image             = each.value.psmdb_image
  pbm_image               = each.value.pbm_image
  pmm_client_image        = each.value.pmm_client_image  
  network_name            = each.value.network_name  
  enable_ldap             = each.value.enable_ldap
  ldap_servers            = each.value.ldap_servers
  ldap_bind_dn            = each.value.ldap_bind_dn
  ldap_bind_pw            = each.value.ldap_bind_pw
  ldap_user_search_base   = each.value.ldap_user_search_base
  enable_oidc             = each.value.enable_oidc
  oidc_issuer             = each.value.oidc_issuer
  oidc_audience           = each.value.oidc_audience
  oidc_client_id          = each.value.oidc_client_id
  oidc_auth_name_prefix   = each.value.oidc_auth_name_prefix
  oidc_principal_name     = each.value.oidc_principal_name
  oidc_authorization_claim = each.value.oidc_authorization_claim
  pki_certs_volume_name   = each.value.pki_certs_volume_name
#  enable_tls              = each.value.enable_tls
#  tls_cert_file           = each.value.tls_cert_file
#  tls_key_file            = each.value.tls_key_file
#  tls_ca_file             = each.value.tls_ca_file  
#  enable_encryption_rest  = each.value.enable_encryption_rest
#  vault_addr              = each.value.vault_addr
#  vault_token             = each.value.vault_token
#  vault_kv_path           = each.value.vault_kv_path
#  vault_pki_role          = each.value.vault_pki_role  
  bind_to_localhost       = each.value.bind_to_localhost
  enable_pmm              = each.value.enable_pmm
  enable_pbm              = each.value.enable_pbm

  depends_on = [
    module.pmm_server,
    module.minio_server,
    module.ldap_server,
    module.vault_server,
    module.keycloak_server
  ]
}

module "pmm_server" {
  source                  = "./modules/pmm_server"
  for_each                = var.pmm_servers
  pmm_host                = each.key
  domain_name             = each.value.domain_name
  env_tag                 = each.value.env_tag
  pmm_server_image        = each.value.pmm_server_image
  pmm_port                = each.value.pmm_port
  pmm_external_port       = each.value.pmm_external_port
  watchtower_token        = each.value.watchtower_token
  pmm_server_user         = each.value.pmm_server_user
  pmm_server_pwd          = each.value.pmm_server_pwd
  renderer_image          = each.value.renderer_image
  watchtower_image        = each.value.watchtower_image
  network_name            = each.value.network_name  
  bind_to_localhost       = each.value.bind_to_localhost
}

module "minio_server" {
  source                  = "./modules/minio_server"
  for_each                = var.minio_servers
  minio_server            = each.key
  domain_name             = each.value.domain_name  
  env_tag                 = each.value.env_tag
  minio_image             = each.value.minio_image
  minio_mc_image          = each.value.minio_mc_image
  minio_port              = each.value.minio_port
  minio_console_port      = each.value.minio_console_port
  minio_access_key        = each.value.minio_access_key
  minio_secret_key        = each.value.minio_secret_key
  bucket_name             = each.value.bucket_name
  backup_retention        = each.value.backup_retention
  network_name            = each.value.network_name  
  bind_to_localhost       = each.value.bind_to_localhost
}

module "ldap_server" {
  source = "./modules/ldap_server"
  for_each                = var.ldap_servers
  ldap_server             = each.key
  domain_name             = each.value.domain_name  
  env_tag                 = each.value.env_tag
  ldap_image              = each.value.ldap_image
  ldap_admin_image        = each.value.ldap_admin_image
  ldap_port               = each.value.ldap_port
  ldap_admin_port         = each.value.ldap_admin_port
  ldap_domain             = each.value.ldap_domain
  ldap_org                = each.value.ldap_org
  ldap_admin_password     = each.value.ldap_admin_password
  ldap_users              = each.value.ldap_users
  network_name            = each.value.network_name  
  bind_to_localhost       = each.value.bind_to_localhost
}

module "keycloak_server" {
  source                  = "./modules/keycloak_server"
  for_each                = var.keycloak_servers
  keycloak_server         = each.key
  domain_name             = each.value.domain_name
  env_tag                 = each.value.env_tag
  keycloak_image          = each.value.keycloak_image
  keycloak_port           = each.value.keycloak_port
  keycloak_https_port     = each.value.keycloak_https_port
  pki_certs_volume_name   = each.value.pki_certs_volume_name
  keycloak_external_port  = each.value.keycloak_external_port
  keycloak_admin_user     = each.value.keycloak_admin_user
  keycloak_admin_password = each.value.keycloak_admin_password
  oidc_realm              = each.value.oidc_realm
  oidc_client_id          = each.value.oidc_client_id
  oidc_client_secret      = each.value.oidc_client_secret
  oidc_users              = each.value.oidc_users
  network_name            = each.value.network_name
  bind_to_localhost       = each.value.bind_to_localhost

  depends_on = [module.vault_server]
}

module "vault_server" {
  source                = "./modules/vault_server"
  for_each              = var.vault_servers
  vault_container_name  = each.key
  vault_image           = each.value.vault_image
  vault_port            = each.value.vault_port
  vault_token           = each.value.vault_token
  vault_pki_common_name = each.value.vault_pki_common_name
  vault_cert_domain     = each.value.vault_cert_domain
  vault_kv_path_prefix  = each.value.vault_kv_path_prefix
  vault_kv_path         = each.value.vault_kv_path
  vault_pki_role        = each.value.vault_pki_role
  vault_keycloak_role   = each.value.vault_keycloak_role
  keycloak_common_name  = each.value.keycloak_common_name
  pki_certs_volume_name = each.value.pki_certs_volume_name
  network_name          = each.value.network_name
  bind_to_localhost     = each.value.bind_to_localhost
}
