# Deploy MongoDB environments using Terraform/Ansible

This automation framework deploys the full stack of Percona Software for MongoDB easily:

- Percona Server for MongoDB (PSMDB)
- Percona Backup for MongoDB (PBM)
- Percona Monitoring & Management (PMM)

You can choose between:

- Creating all resources in a public cloud platform (AWS, GCP, Azure) or a private CHAOS
  cluster, using a combination of Terraform and Ansible.
- Run everything locally on a single server or your own laptop using Docker containers or
  Libvirt/KVM virtual machines (Terraform only — Ansible is not required).

## Web UI (Recommended)

A zero-dependency web frontend (written in Go) is available in [`ui-go/`](./ui-go/README.md).
It lets you configure, deploy, stop, restart, and destroy MongoDB environments through a
browser instead of editing `.tfvars` files by hand.

Key features:
- Visual wizard for cluster topology, images/packages, credentials, and networking
- Live deployment log streamed in the browser via Server-Sent Events
- Hosts & Connections panel with one-click SSH/`docker exec` commands, MongoDB connection
  strings, and direct links to PMM and MinIO Console web UIs
- Multiple concurrent environments supported — each gets its own prefixed inventory and
  SSH config files (e.g. `myenv_inventory_cl01`, `myenv_ssh_config_cl01`)

```bash
cd ui-go
go run .
# then open http://127.0.0.1:5001
```

See [`ui-go/README.md`](./ui-go/README.md) for full details.

## Manual Instructions (without the Web UI)

1. Clone this repository on your machine and `cd` to it

    ```
    git clone https://github.com/percona/mongo_terraform_ansible.git
    cd mongo_terraform_ansible
    ```

2. Go to your desired target platform's subdirectory. Example:
    ```
    cd terraform/gcp
    ```

3. Follow the instructions on the README inside the subdirectory of your desired platform.

    - [AWS](./terraform/aws/README.md)
    - [GCP](./terraform/gcp/README.md)
    - [Azure](./terraform/azure/README.md)
    - [CHAOS](./terraform/chaos/README.md)
    - [Local Docker containers](./terraform/docker/README.md)
    - [Local Libvirt/KVM virtual machines](./terraform/libvirt/README.md)

## Disclaimer: This code is not supported by Percona. It has been provided solely as a community-contributed example and is not covered under any Percona services agreement.
