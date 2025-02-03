# Deploy hardware for MongoDB clusters using Terraform in Docker

Deploy the full stack of Percona MongoDB software on Docker containers:

- Percona Server for MongoDB
- Percona Backup for MongoDB
- PMM Client
- PMM Server 

For the backup storage, a MinIO server is deployed and a storage bucket is configured as the backup destination for PBM.

## Pre-requisites

- For a Macbook it is recommended to install Homebrew. From a Terminal run:
  
  ```
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  ```

- Install Terraform. Using Homebrew you can do:
  
  ```
  brew install terraform
  ```
  
  See the [Terraform installation documentation](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli#install-terraform) for detailed instructions on other platforms.

- Install Docker. Using Homebrew run:
  
  ```
  brew install docker --cask
  ```
  
  See the [Docker installation documentation](https://docs.docker.com/engine/install/) for detailed instructions on other platforms.

- Start Docker Desktop by opening the Docker app.

0. Clone this repository on your machine

    ```
    git clone https://github.com/percona/mongo_terraform_ansible.git
    ```

1. Go to the directory
    
    ```
    cd mongo_terraform_ansible/terraform/docker
    ```

1. Initialize Terraform 

    ```
    terraform init
    ```

## Quick guide

1. Review and edit the configuration file if needed. By default a 2-shard cluster is deployed, where each shard is 3 node Replica Set.


    ```
    vi variables.tf
    ```

2. Run Terraform to create the resources

    ```
    terraform apply
    ``` 

3. Check that created containers are running correctly

    ```
    docker ps -a
    ```

4. Connect to a mongos router to access the cluster. For example:

    ```
    docker exec -it test-mongos00 mongosh admin -u root -p percona
    sh.status()
    ```

- Access PMM Server by opening a web browser at https://127.0.0.1:443. The default credentials are admin/admin
- A `pbm-cli` container is deployed where you can run PBM commands. Example:
  ```
  docker exec -it test-pbm-cli pbm status
  ```
- Access the Minio web interface at http://127.0.0.1:9001 to see the backup storage. The default credentials are minio/minioadmin
- Grafana renderer is installed and configured in order to be able to export PMM graphs as PNG
- There is no need to run the Ansible playbooks when deploying MongoDB via the Docker images


## Cleanup

1. Run terraform to remove all the resources 
  ```
  terraform destroy
  ```

## Running a workload

- To be able to run test workloads, a YCSB container is created as part of the stack. A sharded `ycsb` collection is automatically created with `{_id: hashed }` as the shard key. 

To run a YCSB workload:

1. Start a shell session inside the YCSB container
````
docker exec -it test-ycsb /bin/bash
```

2. Perform initial data load
```
/ycsb/bin/ycsb.sh load mongodb -P /ycsb/workloads/workloada -p mongodb.url="mongodb://root:percona@test-mongos00:27017/"
```

3. Run the benchmark
```
/ycsb/bin/ycsb.sh run mongodb -s -P /ycsb/workloads/workloada -p operationcount=1500000 -threads 4 -p mongodb.url="mongodb://root:percona@test-mongos00:27017/"
```
