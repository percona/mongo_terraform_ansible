# Minimum standalone replica-set deployment.
prefix = "myenv"

clusters = {}

replsets = {
  rs01 = {
    enable_pmm = false
    enable_pbm = false
  }
}

pmm_servers   = {}
minio_servers = {}
ldap_servers  = {}
