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

provider "docker" {
}

module "mongodb_clusters" {
  source = "./modules/mongodb_cluster"
  for_each = var.clusters
  cluster_name = each.key
  env_tag    = each.value.env_tag
  configsvr_count = each.value.configsvr_count
  shard_count = each.value.shard_count
  shardsvr_replicas = each.value.shardsvr_replicas
  arbiters_per_replset = each.value.arbiters_per_replset
  mongos_count = each.value.mongos_count  
  pmm_host = var.pmm_host
  pmm_port = var.pmm_port  
  pmm_server_user =var.pmm_server_user
  pmm_server_pwd = var.pmm_server_pwd
  minio_server = var.minio_server
  minio_port = var.minio_port
  bind_to_localhost = each.value.bind_to_localhost

  depends_on = [docker_container.pmm,null_resource.minio_bucket,docker_image.pbm_mongod]
}

module "mongodb_replsets" {
  source = "./modules/mongodb_replset"
  for_each = var.replsets
  rs_name = each.key
  env_tag    = each.value.env_tag
  data_nodes_per_replset = each.value.data_nodes_per_replset
  arbiters_per_replset = each.value.arbiters_per_replset
  pmm_host = var.pmm_host
  pmm_port = var.pmm_port  
  pmm_server_user = var.pmm_server_user
  pmm_server_pwd = var.pmm_server_pwd
  minio_server = var.minio_server
  minio_port = var.minio_port
  bind_to_localhost = each.value.bind_to_localhost
  
  depends_on = [docker_container.pmm,null_resource.minio_bucket,docker_image.pbm_mongod]
}