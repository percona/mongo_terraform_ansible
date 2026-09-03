# Minimum x86_64 Libvirt deployment.
# Download the selected image into sources/ before applying.
hosts     = 3
hostnames = ["db-1", "db-2", "db-3"]
source_vm = "sources/rocky9.qcow2"
arch      = "x86_64"
