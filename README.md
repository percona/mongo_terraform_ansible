# Deploy MongoDB environments using Terraform/Ansible

This automation framework deploys the full stack of Percona Software for MongoDB easily:

- Percona Server for MongoDB (PSMDB)
- Percona Backup for MongoDB (PBM)
- Percona Monitoring & Management (PMM)

You can choose between:

- Creating all resources in a public cloud platform, using a combination of Terraform and Ansible.
- Run everything in Docker containers on a single server (even your own laptop) with Terraform (Ansible is not required in this case).

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
    - [Docker](./terraform/docker/README.md)

## Disclaimer: This code is not supported by Percona. It has been provided solely as a community-contributed example and is not covered under any Percona services agreement.
