# Deploy VMs using Terraform with Libvirt/KVM

This module creates:

- Libvirt Storage Pool
- OS Images and Resized Disk Volumes
- Cloud-Init ISOs for configuration
- Private Network (NAT mode)
- KVM Domains (VMs)

## Prerequisites

### 1. Install KVM/Libvirt

Ensure you have a KVM-capable Linux host.

**Fedora:**
```bash
sudo dnf install @virtualization -y
```

**Ubuntu/Debian:**
```bash
sudo apt install qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils
```

### 2. Configure Libvirt

Define the storage pool and add your user to the libvirt group:

```bash
# Create a directory for volumes if it doesn't exist
mkdir -p $PWD/volumes

# Define the default pool
sudo virsh pool-define-as --name default --type dir --target $PWD/volumes
sudo virsh pool-start default
sudo virsh pool-autostart default

# Add user to libvirt group (requires logout/login or new shell to take effect)
sudo usermod -aG libvirt $USER
```

### 3. Install Requirements

- **Terraform** or **OpenTofu**: [Install Guide](https://opentofu.org/docs/intro/install/)
- **mkisofs** (required for Cloud-Init generation):
    - Fedora: `sudo dnf install genisoimage`
    - Debian/Ubuntu: `sudo apt install genisoimage`

## Quick Guide

1. **Change into this directory:**
   ```bash
   cd mongo_terraform_ansible/terraform/libvirt
   ```

2. **Generate SSH Keys:**
   Create a specific key pair for these VMs:
   ```bash
   mkdir -p ssh_keys
   ssh-keygen -b 2048 -t rsa -f ./ssh_keys/opentofu -q -N ""
   ```

3. **Download OS Images:**
   Download the cloud image you want to use into the `sources` directory.

   **Rocky Linux 9:**
   ```bash
   curl --output-dir "sources" --create-dirs -L -o rocky9.qcow2 https://download.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud-Base.latest.x86_64.qcow2
   ```

   **Debian 12:**
   ```bash
   curl --output-dir "sources" --create-dirs -L -o debian12.qcow2 https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2
   ```

4. **Initialize Terraform:**
   ```bash
   terraform init
   # OR
   tofu init
   ```

5. **Review and apply:**
   Check `variables.tf` and adjust if needed, then deploy:
   ```bash
   terraform apply
   # OR
   tofu apply
   ```

## Connecting to Instances

The VMs are configured with the SSH key generated in step 2. The IP addresses are defined in `variables.tf` (default `192.168.100.10` etc.).

```bash
ssh -i ./ssh_keys/opentofu rocky@192.168.100.10
```
*(User might be `debian`, `ubuntu`, or `rocky` depending on the image)*

## Variables to Customize

Edit `variables.tf` to customize your deployment:

- **hosts**: Number of VMs to create (default: `3`).
- **hostnames**: List of hostnames for the VMs.
- **memory**: List of RAM size in MB for each VM (default: `2048`).
- **vcpu**: Number of vCPUs per VM (default: `2`).
- **ips**: List of static IP addresses for the VMs.
- **source_vm**: Path to the source qcow2 image relative to the module root (default: `sources/rocky9.qcow2`).
- **interface**: Host network interface to bridge/nat (default: `ens01`).

## Notes

- This module provisions only virtual machines and base access. It does not run the Ansible MongoDB deployment automatically.
- After the VMs are reachable, use the playbooks in [`../../ansible`](../../ansible) if you want the full MongoDB software stack installed.
- Topology expansion automation in this repository targets AWS, GCP, Azure, CHAOS, and Docker. For Libvirt, provision any additional VMs manually and then run the appropriate Ansible playbook (`add_shard.yml` or `add_replset_member.yml`) with an inventory that includes the new hosts.

## Shutdown VMs

To shutdown the VMs using Terraform/OpenTofu:

```bash
terraform apply -var 'vm_condition_poweron=false'
# OR
tofu apply -var 'vm_condition_poweron=false'
```

## Credits

This project makes extensive use of the excellent [terraform-provider-libvirt](https://github.com/dmacvicar/terraform-provider-libvirt). Special thanks to the maintainers for allowing us to manage KVM/Libvirt resources with Terraform.
