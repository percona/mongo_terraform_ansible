resource "local_file" "AnsibleInventoryCluster" {
  for_each = module.mongodb_clusters

  content = templatefile("inventory_cluster.tmpl",
    {
      ansible_group_shards     = each.value.ansible_group_shards
      ansible_group_index      = each.value.ansible_group_index
      hostname_shards          = each.value.hostname_shards
      ip_shards                = each.value.ip_shards

      ansible_group_cfg        = each.value.ansible_group_cfg
      hostname_cfg             = each.value.hostname_cfg
      ip_cfg                   = each.value.ip_cfg

      ansible_group_mongos     = each.value.ansible_group_mongos
      hostname_mongos          = each.value.hostname_mongos
      ip_mongos                = each.value.ip_mongos

      ansible_group_arbiters   = each.value.ansible_group_arbiters
      ansible_group_arb_index  = each.value.ansible_group_arb_index
      hostname_arbiters        = each.value.hostname_arbiters
      ip_arbiters              = each.value.ip_arbiters

      number_of_shards         = each.value.number_of_shards
      arbiters_per_replset     = range(each.value.arbiters_per_replset)

      my_ssh_user              = var.my_ssh_user
      cluster                  = each.value.cluster
      region                   = each.value.region
      hostname_pmm             = local.pmm_host
      bucket                   = google_storage_bucket.mongo-backups.name
      endpointUrl              = var.gcloud_storage_endpoint
      access_key               = google_storage_hmac_key.mongo-backup-service-account.access_id
      secret_access_key        = google_storage_hmac_key.mongo-backup-service-account.secret      
    }
  )

  filename = "inventory_${each.key}"
}

resource "local_file" "SSHConfigCluster" {
  for_each = module.mongodb_clusters

  content = templatefile("ssh_config_cluster.tmpl", {
    ansible_group_shards   = each.value.ansible_group_shards
    hostname_shards        = each.value.hostname_shards
    ip_shards              = each.value.ip_shards
    ansible_group_cfg      = each.value.ansible_group_cfg
    hostname_cfg           = each.value.hostname_cfg
    ip_cfg                 = each.value.ip_cfg
    ansible_group_mongos   = each.value.ansible_group_mongos
    hostname_mongos        = each.value.hostname_mongos
    ip_mongos              = each.value.ip_mongos
    hostname_arbiters      = each.value.hostname_arbiters
    ip_arbiters            = each.value.ip_arbiters
    my_ssh_user            = var.my_ssh_user
    enable_ssh_gateway     = var.enable_ssh_gateway
    hostname_pmm           = local.pmm_host
    public_ip_pmm          = google_compute_instance.pmm.network_interface.0.access_config.0.nat_ip
  })

  filename = "ssh_config_${each.key}"
}

resource "local_file" "AnsibleInventoryRS" {
  for_each = module.mongodb_replsets

  content = templatefile("inventory_replset.tmpl",
    {
      ansible_group_replsets     = each.value.ansible_group_replsets
      hostname_replsets          = each.value.hostname_replsets
      ip_replsets                = each.value.ip_replsets

      ansible_group_arbiters   = each.value.ansible_group_arbiters
      hostname_arbiters        = each.value.hostname_arbiters
      ip_arbiters              = each.value.ip_arbiters

      my_ssh_user              = var.my_ssh_user
      rs_name                  = each.value.rs_name
      region                   = each.value.region
      hostname_pmm             = local.pmm_host
      bucket                   = google_storage_bucket.mongo-backups.name
      endpointUrl              = var.gcloud_storage_endpoint
      access_key               = google_storage_hmac_key.mongo-backup-service-account.access_id
      secret_access_key        = google_storage_hmac_key.mongo-backup-service-account.secret      
    }
  )

  filename = "inventory_${each.key}"
}

resource "local_file" "SSHConfigRS" {
  for_each = module.mongodb_replsets

  content = templatefile("ssh_config_rs.tmpl", {
    ansible_group_replsets     = each.value.ansible_group_replsets
    hostname_replsets          = each.value.hostname_replsets
    ip_replsets                = each.value.ip_replsets
    ansible_group_arbiters   = each.value.ansible_group_arbiters
    hostname_arbiters      = each.value.hostname_arbiters
    ip_arbiters            = each.value.ip_arbiters
    my_ssh_user            = var.my_ssh_user
    enable_ssh_gateway     = var.enable_ssh_gateway
    hostname_pmm           = local.pmm_host
    public_ip_pmm          = google_compute_instance.pmm.network_interface.0.access_config.0.nat_ip
  })

  filename = "ssh_config_${each.key}"
}