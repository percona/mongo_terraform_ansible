terraform {
  required_version = ">= 1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

module "mongodb_clusters" {
  source                 = "./modules/mongodb_cluster"
  for_each               = var.clusters
  cluster_name           = each.key
  prefix                 = var.prefix
  env_tag                = each.value.env_tag
  configsvr_count        = each.value.configsvr_count
  shard_count            = each.value.shard_count
  shardsvr_replicas      = each.value.shardsvr_replicas
  arbiters_per_replset   = each.value.arbiters_per_replset
  mongos_count           = each.value.mongos_count
  resource_group_name    = local.resource_group_name
  vnet_name              = local.vnet_name
  subnet                 = azurerm_subnet.subnet.id
  location               = var.location
  subnet_cidr            = var.subnet_cidr
  ssh_users              = var.ssh_users
  my_ssh_user            = var.my_ssh_user
  image = {
    publisher = var.image.publisher
    offer     = var.image.offer
    sku       = var.image.sku
    version   = var.image.version
  }
  use_spot_instances     = var.use_spot_instances
  data_disk_type         = var.data_disk_type

  depends_on = [
    azurerm_storage_account.mongo_backups,
    azurerm_subnet.subnet
  ]
}

module "mongodb_replsets" {
  source                   = "./modules/mongodb_replset"
  for_each                 = var.replsets
  rs_name                  = each.key
  prefix                   = var.prefix
  env_tag                  = each.value.env_tag
  data_nodes_per_replset   = each.value.data_nodes_per_replset
  arbiters_per_replset     = each.value.arbiters_per_replset
  resource_group_name      = local.resource_group_name  
  vnet_name                = local.vnet_name
  subnet                   = azurerm_subnet.subnet.id
  location                 = var.location
  my_ssh_user              = var.my_ssh_user
  ssh_users                = var.ssh_users
  image = {
    publisher = var.image.publisher
    offer     = var.image.offer
    sku       = var.image.sku
    version   = var.image.version
  }
  use_spot_instances       = var.use_spot_instances
  data_disk_type           = var.data_disk_type

  depends_on = [
    azurerm_storage_account.mongo_backups,
    azurerm_subnet.subnet
  ]
}