resource "google_storage_bucket" "mongo-backups" {
  name          = "${var.env_tag}-${var.bucket_name}"
  location      = var.region
  force_destroy = true
  uniform_bucket_level_access = true

  lifecycle_rule {
    condition {
      age = "${var.backup_retention}"
    }
    action {
      type = "Delete"
    }
  }
}

resource "google_service_account" "mongo-backup-service-account" {
  account_id   = "${var.env_tag}-mongo-backup-sa"
  display_name = "Mongo Backup Service Account"
}

resource "google_storage_hmac_key" "mongo-backup-service-account" {
  service_account_email = google_service_account.mongo-backup-service-account.email
}

resource "google_storage_bucket_iam_binding" "binding" {
  bucket = google_storage_bucket.mongo-backups.name
  role = "roles/storage.admin"
    members = [
      "serviceAccount:${google_service_account.mongo-backup-service-account.email}",
    ]
}

output "access_key" {
  value = google_storage_hmac_key.mongo-backup-service-account.access_id
}

output "secret_key" {
  value     = google_storage_hmac_key.mongo-backup-service-account.secret
  sensitive = true
}
