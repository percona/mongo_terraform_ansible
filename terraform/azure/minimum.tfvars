# Minimum standalone replica-set deployment.
# Supply Azure credentials through ARM_* environment variables or az login.
prefix               = "myenv"
my_ssh_user          = "ubuntu"
ssh_users            = { ubuntu = "/absolute/path/to/id_ed25519.pub" }
ssh_private_key_path = "/absolute/path/to/id_ed25519"

clusters   = {}
enable_pmm = false

replsets = {
  rs01 = {
    enable_pmm = false
    enable_pbm = false
  }
}
