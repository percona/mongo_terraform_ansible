terraform {
  required_version = ">= 1.0" 
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }

  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

module "mongodb_clusters" {
  source = "./modules/mongodb_cluster"
  for_each          = var.clusters
  cluster_name      = each.key
  prefix            = var.prefix  
  env_tag           = each.value.env_tag
  configsvr_count = each.value.configsvr_count
  shard_count = each.value.shard_count
  shardsvr_replicas = each.value.shardsvr_replicas
  arbiters_per_replset = each.value.arbiters_per_replset
  mongos_count = each.value.mongos_count  
  vpc               = local.vpc
  subnet_name       = var.subnet_name
  region            = var.region
  subnet_cidr       = var.subnet_cidr
  gce_ssh_users     = var.gce_ssh_users
  my_ssh_user       = var.my_ssh_user
  image             = var.image
  use_spot_instances = var.use_spot_instances
  data_disk_type    = var.data_disk_type  

  depends_on = [google_storage_bucket.mongo-backups, google_compute_subnetwork.vpc-subnet]
}

module "mongodb_replsets" {
  source = "./modules/mongodb_replset"
  for_each           = var.replsets
  rs_name            = each.key
  prefix             = var.prefix  
  env_tag            = each.value.env_tag
  data_nodes_per_replset = each.value.data_nodes_per_replset
  arbiters_per_replset = each.value.arbiters_per_replset
  vpc                = local.vpc
  subnet_name        = var.subnet_name
  region             = var.region
  my_ssh_user        = var.my_ssh_user
  gce_ssh_users      = var.gce_ssh_users
  image              = var.image
  use_spot_instances = var.use_spot_instances
  data_disk_type     = var.data_disk_type     

 depends_on = [google_storage_bucket.mongo-backups,  google_compute_subnetwork.vpc-subnet]
 }
