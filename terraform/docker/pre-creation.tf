resource "local_file" "mongodb_keyfile" {
  filename = "/tmp/mongodb-keyfile.key"
  content  = <<-EOT
    12345678901234
  EOT

  file_permission = "0600"
}

# Generate the file content with templatefile
locals {
  storage_config_content = templatefile("pbm-storage.tmpl", {
    minio_region     = var.minio_region
    bucket_name      = var.bucket_name
    env_tag          = var.env_tag
    minio_server     = "minio-server:9000"
    minio_access_key = var.minio_access_key
    minio_secret_key = var.minio_secret_key
  })
}

# Write the generated content to a file
resource "local_file" "storage_config" {
  filename = "${path.module}/pbm-storage.conf"
  content  = local.storage_config_content
}