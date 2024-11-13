resource "local_file" "mongodb_keyfile" {
  filename = "/tmp/mongodb-keyfile.key"
  content  = <<-EOT
    12345678901234
  EOT

  file_permission = "0600"
}