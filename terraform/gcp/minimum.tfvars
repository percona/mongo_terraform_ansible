# Minimum standalone replica-set deployment.
# Supply GCP credentials through Application Default Credentials or the provider environment.
project_id           = "my-gcp-project"
prefix               = "myenv"
my_ssh_user          = "ubuntu"
gce_ssh_users        = { ubuntu = "/absolute/path/to/id_ed25519.pub" }
ssh_private_key_path = "/absolute/path/to/id_ed25519"

clusters   = {}
enable_pmm = false

replsets = {
  rs01 = {
    enable_pmm = false
    enable_pbm = false
  }
}
