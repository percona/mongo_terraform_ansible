# Minimum standalone replica-set deployment.
# Export CHAOS_API_TOKEN before running Terraform; CHAOS manages SSH keys.
prefix      = "myenv"
my_ssh_user = "your_chaos_username"

clusters     = {}
enable_pmm   = false
enable_minio = false

replsets = {
  rs01 = {
    enable_pmm = false
    enable_pbm = false
  }
}
