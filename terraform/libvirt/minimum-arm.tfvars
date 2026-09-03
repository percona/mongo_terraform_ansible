# Minimum aarch64 Libvirt deployment.
# Install the ARM QEMU packages and use the firmware paths for your host OS.
hosts     = 3
hostnames = ["db-1", "db-2", "db-3"]
source_vm = "sources/debian13-arm64.qcow2"
interface = "enp1s0"
arch      = "aarch64"

# Ubuntu 24.04:
# firmware      = "/usr/share/AAVMF/AAVMF_CODE.no-secboot.fd"
# nvram_template = "/usr/share/AAVMF/AAVMF_VARS.fd"
# Debian 12:
firmware       = "/usr/share/AAVMF/AAVMF_CODE.fd"
nvram_template = "/usr/share/AAVMF/AAVMF_VARS.fd"
