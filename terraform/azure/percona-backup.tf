# Storage Account for MongoDB Backups
resource "azurerm_storage_account" "mongo_backups" {
  name                     = lower(replace("${var.prefix}mongobackup", "-", ""))
  resource_group_name      = local.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  depends_on = [time_sleep.wait_after_rg]
}

# Management Policy to delete old backups
resource "azurerm_storage_management_policy" "mongo_backup_policy" {
  storage_account_id = azurerm_storage_account.mongo_backups.id

  rule {
    name    = "cleanup-old-backups"
    enabled = true

    filters {
      blob_types    = ["blockBlob"]
      prefix_match  = [""] # Empty string means all blobs
    }

    actions {
      base_blob {
        delete_after_days_since_modification_greater_than = var.backup_retention
      }
    }
  }
}

# Storage Container 
resource "azurerm_storage_container" "mongo_backups_container" {
  name                  = "mongo-backups"
  storage_account_name  = azurerm_storage_account.mongo_backups.name
  container_access_type = "private"
}

# Output Storage Access Keys
output "access_key" {
  value = azurerm_storage_account.mongo_backups.primary_access_key
  sensitive = true
}

output "secret_key" {
  value     = azurerm_storage_account.mongo_backups.primary_access_key
  sensitive = true
}