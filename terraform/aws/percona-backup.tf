# Create an S3 bucket for MongoDB backups
resource "aws_s3_bucket" "mongo_backups" {
  bucket        = "${var.env_tag}-${var.bucket_name}"
  force_destroy = true
  tags = {
    Name = "${var.env_tag}-mongo-backups"
    environment    = var.env_tag
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "mongo_backups_lifecycle" {
  bucket = aws_s3_bucket.mongo_backups.id

  rule {
    id      = "BackupLifecycleRule"
    status  = "Enabled"

    expiration {
      days = var.backup_retention
    }
  }
}

resource "aws_s3_bucket_versioning" "mongo_backups_versioning" {
  bucket = aws_s3_bucket.mongo_backups.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Create an IAM role for MongoDB backup service
resource "aws_iam_role" "mongo_backup_service_role" {
  name = "${var.env_tag}-mongo-backup-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# Attach the S3 access policy to the IAM role
resource "aws_iam_role_policy" "mongo_backup_policy" {
  name   = "${var.env_tag}-mongo-backup-policy"
  role   = aws_iam_role.mongo_backup_service_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:DeleteObject"
        ]
        Resource = [
          "${aws_s3_bucket.mongo_backups.arn}",
          "${aws_s3_bucket.mongo_backups.arn}/*"
        ]
      }
    ]
  })
}

# Create an IAM user for the MongoDB backup service
resource "aws_iam_user" "mongo_backup_service_account" {
  name = "${var.env_tag}-mongo-backup-user"
}

# Attach an access policy to the IAM user
resource "aws_iam_user_policy" "mongo_backup_user_policy" {
  name   = "${var.env_tag}-mongo-backup-user-policy"
  user   = aws_iam_user.mongo_backup_service_account.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:DeleteObject"
        ]
        Resource = [
          "${aws_s3_bucket.mongo_backups.arn}",
          "${aws_s3_bucket.mongo_backups.arn}/*"
        ]
      }
    ]
  })
}

# Create access keys for the MongoDB backup service user
resource "aws_iam_access_key" "mongo_backup_access_key" {
  user = aws_iam_user.mongo_backup_service_account.name
}

output "access_key" {
  value = aws_iam_access_key.mongo_backup_access_key.id
}

output "secret_key" {
  value     = aws_iam_access_key.mongo_backup_access_key.secret
  sensitive = true
}