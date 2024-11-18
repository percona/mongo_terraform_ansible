# Deploy hardware for MongoDB clusters using Terraform in Docker

Deploy the full stack of Percona MongoDB software on Docker containers:

- Percona Server for MongoDB
- Percona Backup for MongoDB
- PMM Client
- PMM Server

For backup storage, a MinIO server is deployed and configured. 

## Pre-requisites

- Make sure you have Terraform installed. See https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli#install-terraform

- Make sure you have installed Docker. See https://docs.docker.com/engine/install/

0. Clone this repository on your machine and `cd` to it

    ```
    git clone https://github.com/percona/mongo_terraform_ansible.git
    cd mongo_terraform_ansible/terraform/docker
    ```

1. Initialize Terraform 

    ```
    terraform init
    ```

## Quick guide

1. Review and edit the configuration file if needed

    ```
    vi variables.tf
    ```

2. Run Terraform to create the resources

    ```
    terraform apply
    ``` 

3. Check resources are running correctly

    ```
    docker ps -a
    ```

4. Connect to mongos router to access the cluster. Example:

    ```
    docker exec -it test-mongodb-mongos00 mongosh admin -u root -p percona
    sh.status()
    ```

- Access PMM running on https://127.0.0.1:443. Default credentials are admin/admin. 
- By default a 2 shard cluster is deployed. Each shard is 3 node PSA replicaset.
- A pbm-cli container is deployed where you can run PBM commands. Example:
  ```
  docker exec -it test-mongodb-pbm-cli pbm status
  ```
- No need to use Ansible when deploying via Docker images. 


## Cleanup

1. Run terraform to remove all the resources 
  ```
  terraform destroy
  ```