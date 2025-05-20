# Deploy MongoDB environments using Terraform/Ansible

This automation is meant to deploy the full stack of Percona MongoDB software easily:

- Percona Server for MongoDB
- Percona Backup for MongoDB
- PMM Client
- PMM Server

The code creates instances in Google Cloud or AWS using Terraform, and relies on Ansible to install the software. You also have the option to run all components on a single server using Docker containers (e.g. your own laptop).

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
