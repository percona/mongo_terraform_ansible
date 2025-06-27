# Deploy MongoDB in Docker using Terraform

Deploys the full stack of Percona MongoDB software on Docker containers:

- Percona Server for MongoDB
- Percona Backup for MongoDB
- PMM Client
- PMM Server (with Grafana Renderer)

A storage bucket in MinIO server is created for PBM backups. Logical and physical backup works. 

By default a sharded cluster with 2 shards is created, where each shard is a 3-node Replica Set using a PSA topology. Additional clusters can be created by customizing the `clusters` variable in the `variables.tf` file (you can also override the variable's default value via tfvars):

```
variable "clusters" {
  description = "MongoDB clusters to deploy"
  type = map(object({
    env_tag               = optional(string, "test")                # Name of the environment for the cluster
    configsvr_count       = optional(number, 3)                     # Number of config servers to be used
    shard_count           = optional(number, 2)                     # Number of shards to be created
    shardsvr_replicas     = optional(number, 2)                     # How many data-bearing nodes for each shard's replica set
    arbiters_per_replset  = optional(number, 1)                     # Number of arbiters for each shard's replica set
    mongos_count          = optional(number, 2)                     # Number of mongos routers to provision
    ...
  }))

  default = {
    test01 = {
      env_tag = "test"
    }
}
```

By default, no stand-alone replica sets are provisioned. If you want to provision any replica sets not part of a sharded cluster, change the default value of the `replsets` variable in the `variables.tf` file (you can also override the variable's default value via tfvars):

```
variable "replsets" {
   description = "MongoDB replica sets to deploy"
   type = map(object({
    env_tag                   = optional(string, "test")               # Name of the environment for the replica set
    data_nodes_per_replset    = optional(number, 2)                    # Number of data bearing members for the replica set
    arbiters_per_replset      = optional(number, 1)                    # Number of arbiters for the replica set
    ...
   })) 

   default = {
#     rs01 = {
#       env_tag = "test"
#     }
   }
}
```

## Pre-requisites

- Terraform
- Docker

### Mac

- It is recommended to use Homebrew. From a Terminal run the following to install it:
  
  ```
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  ```

- Install Terraform. If using Homebrew you can do:
  
  ```
  brew install terraform
  ```
  
  See the [Terraform installation documentation](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli#install-terraform) for detailed instructions.

- Install Docker Desktop. Using Homebrew run:
  
  ```
  brew install docker --cask
  ```

You can check the [Docker installation documentation](https://docs.docker.com/engine/install/) for detailed instructions.

- Start Docker Desktop by opening the Docker app using the Finder.

- Go to Settings -> Advanced. Make sure you have ticked the option `Allow the default Docker socket to be used (requires password)`

### Windows

- Install [WSL](https://learn.microsoft.com/en-us/windows/wsl/install)
  Open PowerShell or Windows Command Prompt in administrator mode by right-clicking and selecting "Run as Administrator".

  ```
  wsl --install
  ```

- Install a Linux distribution. For example:
```
wsl --install -d  Ubuntu
```

- Open `Ubuntu` app from Windows Menu and proceed with the creation of a Linux user and password of your choice.

- [Install Terraform](https://developer.hashicorp.com/terraform/install) inside Linux. Example for Ubuntu:

  ```
  wget -O - https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
  sudo apt update && sudo apt install terraform
  ```

- Install [Docker Desltop on WSL](https://docs.docker.com/desktop/features/wsl/#turn-on-docker-desktop-wsl-2). Depending on which version of Windows you are using, Docker Desktop may prompt you to turn on WSL 2 during installation.


## Initial Installation

1. Clone this repository to your machine

    ```
    git clone https://github.com/percona/mongo_terraform_ansible.git
    ```

2. Go to the directory
    
    ```
    cd mongo_terraform_ansible/terraform/docker
    ```

3. Initialize Terraform 

    ```
    terraform init
    ```

If no errors, proceed to the next section.

## User Guide

1. Review and edit the configuration file as needed


    ```
    vi variables.tf
    ```

2. Run Terraform to create the resources

    ```
    terraform apply
    ``` 

3. Check that all the created containers are running correctly

    ```
    docker ps -a
    ```
    Status should be `Up` and `healthy`.

4. For a sharded cluster, connect to a mongos router to access it. For example:

    ```
    docker exec -it cl01-mongos00 mongosh admin -u root -p percona
    sh.status()
    ```

5. For a replica set, connect to any member to access it. For example:

    ```
    docker exec -it rs01-svr0 mongosh admin -u root -p percona
    rs.status()
    ```

- There is no need to run the Ansible playbook for the Docker-based deployments.

## PMM Monitoring

- You can access the PMM Server by opening a web browser at https://127.0.0.1:8443. The default credentials are `admin/admin`.

- Grafana renderer is installed and configured, in order to be able to export any PMM graphic as a PNG image.

## PBM Backup

- A dedicated `pbm-cli` container is deployed where you can run PBM commands. Example:

```
docker exec -it cl01-pbm-cli pbm status
```

- You can access the Minio Server web interface at http://127.0.0.1:9001 to inspect the backup storage/files. The default credentials are `minio/minioadmin`.

## Simulating a workload

- To be able to run test workloads, a YCSB container is created as part of the stack. 
- For sharded clusters, a sharded `ycsb.usertable` collection is automatically created with `{_id: hashed }` as the shard key. 

- To run a YCSB workload:

  1. Start a shell session inside the YCSB container

     ```
     docker exec -it ycsb /bin/bash
     ```

  2. Perform initial data load against one of the mongos containers, using the correct credentials and port number.

     ```
     /ycsb/bin/ycsb load mongodb -P /ycsb/workloads/workloada -p mongodb.url="mongodb://root:percona@cl01-mongos00:27017/"
     ```

  3. Run the benchmark

     ```
     /ycsb/bin/ycsb run mongodb -s -P /ycsb/workloads/workloada -p operationcount=1500000 -threads 4 -p mongodb.url="mongodb://root:percona@cl01-mongos00:27017/"
     ```

## Cleanup

- Run terraform to remove all the resources and start from scratch

  ```
  terraform destroy
  ```
