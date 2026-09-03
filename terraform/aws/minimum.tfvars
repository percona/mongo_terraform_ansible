# Minimum standalone replica-set deployment.
# Supply AWS credentials through the AWS provider environment or profile.
prefix               = "myenv"
my_ssh_user          = "ec2-user"
ssh_public_key_path  = "/absolute/path/to/id_ed25519.pub"
ssh_private_key_path = "/absolute/path/to/id_ed25519"

clusters   = {}
enable_pmm = false

replsets = {
  rs01 = {
    enable_pmm = false
    enable_pbm = false
  }
}
