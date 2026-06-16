# Deploy MongoDB environments using Terraform and Ansible

This repository automates Percona software for MongoDB across cloud and local environments:

- Percona Server for MongoDB (PSMDB)
- Percona Backup for MongoDB (PBM)
- Percona Monitoring and Management (PMM)

Supported deployment targets:

- Public cloud: AWS, GCP, Azure
- Private cloud: CHAOS
- Local: Docker containers or Libvirt/KVM virtual machines

Cloud and CHAOS deployments use Terraform for infrastructure and Ansible for software
configuration. Docker and Libvirt deployments are Terraform-only.

## Prerequisites

Install the tools that match your target platform:

- `git`
- [Terraform](https://developer.hashicorp.com/terraform/downloads) 1.0+
- [Go 1.22+](https://go.dev/doc/install) if you want to use the Web UI
- [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/) for AWS, GCP, Azure, and CHAOS deployments
- [Docker](https://docs.docker.com/get-docker/) for local Docker environments
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html), [Google Cloud SDK](https://cloud.google.com/sdk/docs/install), or [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) for the corresponding cloud provider
- KVM/Libvirt plus `genisoimage` for local Libvirt deployments

You will also need provider credentials or login configured in your shell before running Terraform.

## Web UI (Recommended)

A zero-dependency web frontend (written in Go) is available in [`ui-go/`](./ui-go/README.md).
It lets you configure, deploy, stop, restart, and destroy MongoDB environments through a
browser instead of editing `.tfvars` files by hand.

Key features:
- Visual wizard for cluster topology, images/packages, credentials, and networking
- Audit plugin controls for every cluster and replica set, including enable/disable and custom filter expressions
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

## Expanding Existing Topologies

The framework supports scale-out for existing deployments, but not scale-in.

Supported changes:
- Add shards to an existing sharded cluster by increasing `shard_count`.
- Add data-bearing members to an existing standalone replica set by increasing `data_nodes_per_replset`.
- Add entirely new clusters or standalone replica sets to an existing environment.

Unsupported changes:
- Reducing `shard_count` or `data_nodes_per_replset`.
- Changing `configsvr_count` after a sharded cluster is initialized.
- Changing `shardsvr_replicas` for existing shards.
- Changing `arbiters_per_replset` for existing sharded clusters or standalone replica sets.

For AWS, GCP, Azure, and CHAOS, scale-out is a two-phase operation: Terraform creates the new hosts and Ansible joins them to MongoDB. For example:

```bash
# Add a shard after increasing shard_count and applying Terraform
ansible-playbook -i <prefix>_inventory_<cluster> ansible/add_shard.yml \
  --extra-vars "new_shard_group=shard<N>"

# Add data-bearing replica set members after increasing data_nodes_per_replset
ansible-playbook -i <prefix>_inventory_<rs> ansible/add_replset_member.yml \
  --extra-vars "target_replset=<rs>"
```

For Docker, Terraform performs the supported scale-out operations directly during `terraform apply`.

The Go UI detects topology changes before deployment. Unsupported changes are refused before Terraform runs. Supported cloud scale-out changes run Terraform first and then the required Ansible scale-out playbook automatically.

## Disclaimer: This code is not supported by Percona. It has been provided solely as a community-contributed example and is not covered under any Percona services agreement.
