module "terraform-local-minio" {
  source           = "circa10a/minio/local"
  minio_access_key = var.minio_access_key
  minio_secret_key = var.minio_secret_key
  minio_buckets    = [ var.bucket_name ]
  minio_network_name = docker_network.mongo_network.id
}