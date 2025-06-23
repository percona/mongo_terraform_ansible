# Deploy MongoDB environments using Terraform/Ansible

This automation is meant to deploy the full stack of Percona MongoDB software easily:

- Percona Server for MongoDB
- Percona Backup for MongoDB
- PMM Client
- PMM Server

Choose between:

- Creating resources in public cloud platforms using a combination of Terraform and Ansible.
- Run everything in Docker containers on a single server (even your own laptop) with Terraform alone. 

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
