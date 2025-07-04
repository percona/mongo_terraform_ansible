terraform {
  required_version = ">= 1.0"

  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "3.0.2"
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
  enable_ldap             = each.value.enable_ldap
  ldap_uri                = each.value.ldap_uri
  ldap_bind_dn            = each.value.ldap_bind_dn
  ldap_bind_pw            = each.value.ldap_bind_pw
  ldap_user_search_base   = each.value.ldap_user_search_base    
  bind_to_localhost       = each.value.bind_to_localhost

  depends_on = [
    module.pmm_server,
    module.minio_server  
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
  ldap_uri                = each.value.ldap_uri
  ldap_bind_dn            = each.value.ldap_bind_dn
  ldap_bind_pw            = each.value.ldap_bind_pw
  ldap_user_search_base   = each.value.ldap_user_search_base     
  bind_to_localhost       = each.value.bind_to_localhost

  depends_on = [
    module.pmm_server,
    module.minio_server
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