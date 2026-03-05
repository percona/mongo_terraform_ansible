# Deploy MongoDB environments using Terraform/Ansible

This automation framework deploys the full stack of Percona Software for MongoDB easily:

- Percona Server for MongoDB (PSMDB)
- Percona Backup for MongoDB (PBM)
- Percona Monitoring & Management (PMM)

You can choose between:

- Creating all resources in a public cloud platform, using a combination of Terraform and Ansible.
- Run everything on a single server (even your own laptop) using Terraform alone (Ansible is not required in this case).

## Web UI (Optional)

A zero-dependency web frontend (written in Go) is available in [`ui-go/`](./ui-go/README.md).
It lets you configure, deploy, stop, and destroy MongoDB environments through a browser instead of editing `.tfvars` files by hand.

```bash
cd ui-go
go run .
# then open http://127.0.0.1:5001
```

See [`ui-go/README.md`](./ui-go/README.md) for full details.

## Instructions

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
    - [Local Docker containers](./terraform/docker/README.md)
    - [Local Libvirt/KVM virtual machines](./terraform/libvirt/README.md)

## Disclaimer: This code is not supported by Percona. It has been provided solely as a community-contributed example and is not covered under any Percona services agreement.
