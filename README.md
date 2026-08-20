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

When using the Web UI, configure provider credentials in **Settings**. The UI stores them under `ui-go/secrets/cloud/` and passes isolated credential environment variables to Terraform. Manual CLI usage still requires provider credentials configured in your shell.

### Quickstart for Mac

```
git clone https://github.com/percona/mongo_terraform_ansible.git
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
brew install go
brew install ansible
```

## Web UI (Recommended)

A zero-dependency web frontend (written in Go) is available in [`ui-go/`](./ui-go/README.md).
It lets you configure, deploy, stop, restart, and destroy MongoDB environments through a
browser instead of editing `.tfvars` files by hand.

Key features:
- Visual wizard for cluster topology, images/packages, credentials, and networking
- Audit plugin controls for every cluster and replica set, including enable/disable and custom filter expressions
- Optional YCSB workload generator with UI controls to insert data, start load, and stop load
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

## Advanced Workflows

The root README is a starting point. Detailed operational guidance lives with the component that runs each workflow:

- Existing topology expansion: [UI workflow](./ui-go/README.md#topology-expansion), [Ansible playbooks](./ansible/README.md#running), and each Terraform provider README.
- Workload generation with YCSB: [UI workflow](./ui-go/README.md#ycsb-workloads), [cloud Ansible notes](./ansible/README.md#ycsb-workloads), and [Docker workflow](./terraform/docker/README.md#simulating-a-workload-with-ycsb).
- TLS, Vault-backed encryption, PBM, PMM, stopping, restarting, and reset playbooks: [Ansible README](./ansible/README.md).

## Verification

Run the Go UI test suite after changing the UI or its generated Terraform configuration:

```bash
cd ui-go
go test ./...
```

## Disclaimer: This code is not supported by Percona. It has been provided solely as a community-contributed example and is not covered under any Percona services agreement.
