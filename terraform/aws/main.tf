terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.68.0"
    }
  }
}

provider "aws" {
  region  = var.region
}

module "mongodb_clusters" {
  source = "./modules/mongodb_cluster"
  for_each          = var.clusters
  cluster_name      = each.key
  env_tag           = each.value.env_tag
  configsvr_count   = each.value.configsvr_count
  shard_count       = each.value.shard_count
  shardsvr_replicas = each.value.shardsvr_replicas
  arbiters_per_replset = each.value.arbiters_per_replset
  mongos_count      = each.value.mongos_count  
  vpc               = local.vpc
  region            = var.region

  depends_on = [aws_s3_bucket.mongo_backups, aws_subnet.vpc-subnet]
}

module "mongodb_replsets" {
   source = "./modules/mongodb_replset"
   for_each         = var.replsets
   rs_name          = each.key
   env_tag          = each.value.env_tag
   data_nodes_per_replset = each.value.data_nodes_per_replset
   arbiters_per_replset = each.value.arbiters_per_replset
   vpc              = local.vpc
   region           = var.region

   depends_on = [aws_s3_bucket.mongo_backups, aws_subnet.vpc-subnet]
 }
