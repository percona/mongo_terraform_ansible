# Deploy VMs using Terraform with Libvirt/KVM

This module creates:

- Libvirt Storage Pool
- OS Images and Resized Disk Volumes
- Cloud-Init ISOs for configuration
- Private Network (NAT mode)
- KVM Domains (VMs)

## Prerequisites

### 1. Install KVM/Libvirt

Tested on Debian 12 (Bookworm) and Ubuntu 24.04 LTS.

```bash
sudo apt install -y qemu-kvm libvirt-daemon-system libvirt-clients virtinst genisoimage
sudo usermod -aG libvirt $USER
# log out and back in for group membership to take effect
```

### 2. ARM (aarch64) guests — additional packages

Required only when `arch = "aarch64"`. This enables software emulation of ARM64 guests on an x86_64 host, or native KVM on an ARM64 host.

```bash
sudo apt install -y qemu-system-arm qemu-efi-aarch64
```

Firmware paths (used for the `firmware` and `nvram_template` variables):

| Distro | `firmware` | `nvram_template` |
|---|---|---|
| Ubuntu 24.04 | `/usr/share/AAVMF/AAVMF_CODE.no-secboot.fd` | `/usr/share/AAVMF/AAVMF_VARS.fd` |
| Debian 12 | `/usr/share/AAVMF/AAVMF_CODE.fd` | `/usr/share/AAVMF/AAVMF_VARS.fd` |

> **Note (Ubuntu):** Use `AAVMF_CODE.no-secboot.fd`, not `AAVMF_CODE.fd`. Libvirt selects firmware via descriptor files in `/usr/share/qemu/firmware/`, and `AAVMF_CODE.fd` has no matching descriptor on Ubuntu.
>
> **Note (Debian 12):** `AAVMF_CODE.no-secboot.fd` does not exist. Use `AAVMF_CODE.fd` instead — its descriptor (`60-edk2-aarch64.json`) lists no Secure Boot features, so it is effectively the same non-secboot firmware.

NVRAM files (`/var/lib/libvirt/qemu/nvram/<hostname>_VARS.fd`) are created automatically from the template at apply time — no manual copy step is needed.

### 3. AppArmor fix (x86_64 hosts running aarch64 guests only)

On x86_64 hosts, libvirt runs aarch64 guests as `type='qemu'` (software emulation). Unlike `type='kvm'`, these domains do not automatically receive AppArmor rules granting disk access when the storage pool is outside `/var/lib/libvirt/`. Add a local override once:

```bash
sudo mkdir -p /etc/apparmor.d/abstractions/libvirt-qemu.d
sudo tee /etc/apparmor.d/abstractions/libvirt-qemu.d/local-pool > /dev/null << 'EOF'
/path/to/your/terraform/libvirt/pool/** rwk,
EOF
```

Replace `/path/to/your/terraform/libvirt/pool/` with the absolute path to this directory's `pool/` folder. The change takes effect immediately for new domains — no service restart needed.

### 4. Install OpenTofu or Terraform

[OpenTofu install guide](https://opentofu.org/docs/intro/install/)

## Quick Guide

1. **Change into this directory:**
   ```bash
   cd mongo_terraform_ansible/terraform/libvirt
   ```

2. **Generate SSH Keys:**
   ```bash
   ssh-keygen -b 2048 -t rsa -f ./ssh_keys/opentofu -q -N ""
   ```

3. **Download an OS image** into the `sources` directory:

   **Rocky Linux 9 — x86_64:**
   ```bash
   curl --output-dir sources --create-dirs -L -o rocky9.qcow2 \
     https://download.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud-Base.latest.x86_64.qcow2
   ```

   **Rocky Linux 9 — aarch64:**
   ```bash
   curl --output-dir sources --create-dirs -L -o rocky9-aarch64.qcow2 \
     https://download.rockylinux.org/pub/rocky/9/images/aarch64/Rocky-9-GenericCloud-Base.latest.aarch64.qcow2
   ```

   **Ubuntu 24.04 LTS — x86_64:**
   ```bash
   curl --output-dir sources --create-dirs -L -o ubuntu2404-amd64.img \
     https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
   ```

   **Ubuntu 24.04 LTS — aarch64:**
   ```bash
   curl --output-dir sources --create-dirs -L -o ubuntu2404-arm64.img \
     https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-arm64.img
   ```

   **Debian 12 (Bookworm) — x86_64:**
   ```bash
   curl --output-dir sources --create-dirs -L -o debian12-amd64.qcow2 \
     https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2
   ```

   **Debian 12 (Bookworm) — aarch64:**
   ```bash
   curl --output-dir sources --create-dirs -L -o debian12-arm64.qcow2 \
     https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-arm64.qcow2
   ```

   **Debian 13 (Trixie) — aarch64:**
   ```bash
   curl --output-dir sources --create-dirs -L -o debian13-arm64.qcow2 \
     https://cloud.debian.org/images/cloud/trixie/daily/latest/debian-13-generic-arm64-daily.qcow2
   ```

4. **Initialize and apply:**

   x86_64 (default):
   ```bash
   tofu init
   tofu apply
   ```

   aarch64 — see the [ARM example](#arm-aarch64-example) below.

## Connecting to Instances

```bash
ssh -i ./ssh_keys/opentofu admin@192.168.100.10
```

Default credentials: user `admin`, password `admin`, SSH key from `ssh_keys/opentofu`.

VMs start automatically after `tofu apply`. On first boot cloud-init runs `package_update` and `package_upgrade`, so allow a few minutes before SSH is ready. On aarch64 guests running under software emulation, allow 10–30 minutes — see [Monitoring ARM boot progress](#monitoring-arm-boot-progress).

## Variables

| Variable | Default | Description |
|---|---|---|
| `hosts` | `3` | Number of VMs |
| `hostnames` | `["db-1","db-2","db-3"]` | VM hostnames |
| `memory` | `[2048,2048,2048]` | RAM per VM in MB |
| `vcpu` | `2` | vCPUs per VM |
| `ips` | `["192.168.100.10"…]` | Static IPs |
| `source_vm` | `sources/rocky9.qcow2` | Path to cloud image |
| `interface` | `ens01` | Guest network interface name |
| `arch` | `x86_64` | CPU architecture: `x86_64` or `aarch64` |
| `domain_type` | `qemu` | Libvirt domain type (`qemu` for cross-arch emulation, `kvm` for native) |
| `firmware` | `""` | UEFI firmware path (required for `aarch64`) |
| `nvram_template` | `""` | UEFI NVRAM template path (required for `aarch64`) |

## ARM (aarch64) Example

After completing the ARM prerequisites above:

**Ubuntu 24.04 host:**
```bash
tofu init
tofu apply \
  -var 'arch=aarch64' \
  -var 'source_vm=sources/debian13-arm64.qcow2' \
  -var 'interface=enp1s0' \
  -var 'firmware=/usr/share/AAVMF/AAVMF_CODE.no-secboot.fd' \
  -var 'nvram_template=/usr/share/AAVMF/AAVMF_VARS.fd'
```

**Debian 12 host:**
```bash
tofu init
tofu apply \
  -var 'arch=aarch64' \
  -var 'source_vm=sources/debian13-arm64.qcow2' \
  -var 'interface=enp1s0' \
  -var 'firmware=/usr/share/AAVMF/AAVMF_CODE.fd' \
  -var 'nvram_template=/usr/share/AAVMF/AAVMF_VARS.fd'
```

> **Note:** The network interface inside ARM `virt` machine guests is `enp1s0` (PCIe), not the default `ens01`. Boot time for aarch64 guests on x86_64 hosts is 10–30+ minutes due to software emulation — this is expected.

## Monitoring ARM boot progress

Since aarch64 guests under software emulation take 10–30+ minutes to boot, you can watch the serial console to confirm progress rather than waiting blindly for SSH:

```bash
virsh -c qemu:///system console db-1
```

- This module provisions only virtual machines and base access. It does not run the Ansible MongoDB deployment automatically.
- After the VMs are reachable, use the playbooks in [`../../ansible`](../../ansible) if you want the full MongoDB software stack installed.
- Topology expansion automation in this repository targets AWS, GCP, Azure, CHAOS, and Docker. For Libvirt, provision any additional VMs manually and then run the appropriate Ansible playbook (`add_shard.yml` or `add_replset_member.yml`) with an inventory that includes the new hosts.

## Shutdown VMs

Pass the same `-var` flags used during apply so the plan is consistent:

```bash
# aarch64
tofu apply \
  -var 'vm_condition_poweron=false' \
  -var 'arch=aarch64' \
  -var 'source_vm=sources/debian13-arm64.qcow2' \
  -var 'interface=enp1s0' \
  -var 'firmware=/usr/share/AAVMF/AAVMF_CODE.fd' \
  -var 'nvram_template=/usr/share/AAVMF/AAVMF_VARS.fd'

# x86_64
tofu apply -var 'vm_condition_poweron=false'
```

## Destroy

Pass the same `-var` flags used during apply:

```bash
# aarch64
tofu destroy \
  -var 'arch=aarch64' \
  -var 'source_vm=sources/debian13-arm64.qcow2' \
  -var 'interface=enp1s0' \
  -var 'firmware=/usr/share/AAVMF/AAVMF_CODE.fd' \
  -var 'nvram_template=/usr/share/AAVMF/AAVMF_VARS.fd'

# x86_64
tofu destroy
```

> **Note:** The storage pool directory (`pool/`) contains a `.gitkeep` placeholder file, so `tofu destroy` will fail to delete the pool with "Directory not empty". If that happens, remove the pool from state and undefine it manually:
> ```bash
> tofu state rm libvirt_pool.k8s
> virsh -c qemu:///system pool-undefine k8s
> ```

## Notes

- This module provisions VMs and base access only. It does not run Ansible automatically.
- After the VMs are reachable, use the playbooks in [`../../ansible`](../../ansible) for the MongoDB stack.

This project makes extensive use of the excellent [terraform-provider-libvirt](https://github.com/dmacvicar/terraform-provider-libvirt). Special thanks to the maintainers for allowing us to manage KVM/Libvirt resources with Terraform.
