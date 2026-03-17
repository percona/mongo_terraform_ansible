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

locals {
  # When var.prefix is non-empty prepend it plus a hyphen to every resource
  # name so that containers/volumes from different environments coexist on the
  # same Docker host without collisions.  Matches the prefix the UI embeds in
  # its docker --filter 'name=<prefix>-' stop/restart commands.
  name_prefix = var.prefix != "" ? "${var.prefix}-" : ""
}

module "mongodb_clusters" {
  source                  = "./modules/mongodb_cluster"
  for_each                = var.clusters
  cluster_name            = "${local.name_prefix}${each.key}"
  domain_name             = each.value.domain_name
  env_tag                 = each.value.env_tag
  configsvr_count         = each.value.configsvr_count
  shard_count             = each.value.shard_count
  shardsvr_replicas       = each.value.shardsvr_replicas
  arbiters_per_replset    = each.value.arbiters_per_replset
  mongos_count            = each.value.mongos_count
  mongodb_root_password   = each.value.mongodb_root_password
  pmm_host                = "${local.name_prefix}${each.value.pmm_host}"
  pmm_port                = each.value.pmm_port
  pmm_server_user         = each.value.pmm_server_user
  pmm_server_pwd          = each.value.pmm_server_pwd
  minio_server            = "${local.name_prefix}${each.value.minio_server}"
  minio_port              = each.value.minio_port
  base_os_image           = each.value.base_os_image
  psmdb_image             = each.value.psmdb_image
  pbm_image               = each.value.pbm_image
  pmm_client_image        = each.value.pmm_client_image
  network_name            = "${local.name_prefix}${each.value.network_name}"
  ldap_servers            = "${local.name_prefix}${each.value.ldap_servers}"
  ldap_bind_dn            = each.value.ldap_bind_dn
  ldap_bind_pw            = each.value.ldap_bind_pw
  ldap_user_search_base   = each.value.ldap_user_search_base    
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
    module.ldap_server
  ]
}

module "mongodb_replsets" {
  source                  = "./modules/mongodb_replset"
  for_each                = var.replsets
  rs_name                 = "${local.name_prefix}${each.key}"
  domain_name             = each.value.domain_name
  env_tag                 = each.value.env_tag
  data_nodes_per_replset  = each.value.data_nodes_per_replset
  arbiters_per_replset    = each.value.arbiters_per_replset
  replset_port            = each.value.replset_port
  arbiter_port            = each.value.arbiter_port
  mongodb_root_password   = each.value.mongodb_root_password  
  pmm_host                = "${local.name_prefix}${each.value.pmm_host}"
  pmm_port                = each.value.pmm_port
  pmm_server_user         = each.value.pmm_server_user
  pmm_server_pwd          = each.value.pmm_server_pwd
  minio_server            = "${local.name_prefix}${each.value.minio_server}"
  minio_port              = each.value.minio_port
  base_os_image           = each.value.base_os_image  
  psmdb_image             = each.value.psmdb_image
  pbm_image               = each.value.pbm_image
  pmm_client_image        = each.value.pmm_client_image  
  network_name            = "${local.name_prefix}${each.value.network_name}"
  enable_ldap             = each.value.enable_ldap
  ldap_servers            = "${local.name_prefix}${each.value.ldap_servers}"
  ldap_bind_dn            = each.value.ldap_bind_dn
  ldap_bind_pw            = each.value.ldap_bind_pw
  ldap_user_search_base   = each.value.ldap_user_search_base
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
    module.ldap_server
  ]
}

module "pmm_server" {
  source                  = "./modules/pmm_server"
  for_each                = var.pmm_servers
  pmm_host                = "${local.name_prefix}${each.key}"
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
  network_name            = "${local.name_prefix}${each.value.network_name}"
  bind_to_localhost       = each.value.bind_to_localhost
}

module "minio_server" {
  source                  = "./modules/minio_server"
  for_each                = var.minio_servers
  minio_server            = "${local.name_prefix}${each.key}"
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
  network_name            = "${local.name_prefix}${each.value.network_name}"
  bind_to_localhost       = each.value.bind_to_localhost
}

module "ldap_server" {
  source = "./modules/ldap_server"
  for_each                = var.ldap_servers
  ldap_server             = "${local.name_prefix}${each.key}"
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
  network_name            = "${local.name_prefix}${each.value.network_name}"
  bind_to_localhost       = each.value.bind_to_localhost
}
