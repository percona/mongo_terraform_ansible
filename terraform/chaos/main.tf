terraform {
  required_version = ">= 1.0"
  required_providers {
    chaos = {
      source  = "percona/chaos"
      version = "~> 1.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

provider "chaos" {
  api_token = var.chaos_api_token
}

module "mongodb_clusters" {
  source   = "./modules/mongodb_cluster"
  for_each = var.clusters

  cluster_name         = each.key
  prefix               = var.prefix
  env_tag              = each.value.env_tag
  configsvr_count      = each.value.configsvr_count
  shard_count          = each.value.shard_count
  shardsvr_replicas    = each.value.shardsvr_replicas
  arbiters_per_replset = each.value.arbiters_per_replset
  mongos_count         = each.value.mongos_count

  my_ssh_user       = var.my_ssh_user
  os_image          = var.os_image
  delete_after_days = var.delete_after_days

  shardsvr_cpu_cores    = var.shardsvr_cpu_cores
  shardsvr_memory_gb    = var.shardsvr_memory_gb
  shardsvr_volume_size  = var.shardsvr_volume_size
  configsvr_cpu_cores   = var.configsvr_cpu_cores
  configsvr_memory_gb   = var.configsvr_memory_gb
  configsvr_volume_size = var.configsvr_volume_size
  mongos_cpu_cores      = var.mongos_cpu_cores
  mongos_memory_gb      = var.mongos_memory_gb
  arbiter_cpu_cores     = var.arbiter_cpu_cores
  arbiter_memory_gb     = var.arbiter_memory_gb

  source_ranges  = var.source_ranges
  firewall_rules = var.firewall_rules

}

module "mongodb_replsets" {
  source   = "./modules/mongodb_replset"
  for_each = var.replsets

  rs_name                = each.key
  prefix                 = var.prefix
  env_tag                = each.value.env_tag
  data_nodes_per_replset = each.value.data_nodes_per_replset
  arbiters_per_replset   = each.value.arbiters_per_replset

  my_ssh_user       = var.my_ssh_user
  os_image          = var.os_image
  delete_after_days = var.delete_after_days

  replsetsvr_cpu_cores   = var.replsetsvr_cpu_cores
  replsetsvr_memory_gb   = var.replsetsvr_memory_gb
  replsetsvr_volume_size = var.replsetsvr_volume_size
  arbiter_cpu_cores      = var.arbiter_cpu_cores
  arbiter_memory_gb      = var.arbiter_memory_gb

  source_ranges  = var.source_ranges
  firewall_rules = var.firewall_rules

}
