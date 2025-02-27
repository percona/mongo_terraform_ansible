# Deploy hardware for MongoDB clusters using Terraform in Docker

Deploy the full stack of Percona MongoDB software on Docker containers:

- Percona Server for MongoDB
- Percona Backup for MongoDB
- PMM Client
- PMM Server with Grafana Renderer

- A MinIO server with a storage bucket is created for PBM backups. Logical and physical backup functionality works. 

- By default 1 sharded cluster with 2 shards is created, where each shard is a 3-node Replica Set using a PSA topology. Additional clusters or replica sets can be created by customizing the variables.tf file


## Pre-requisites

### Mac

- It is recommended to install Homebrew. From a Terminal run:
  
  ```
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  ```

- Install Terraform. Using Homebrew you can do:
  
  ```
  brew install terraform
  ```
  
  See the [Terraform installation documentation](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli#install-terraform) for detailed instructions.

- Install Docker. Using Homebrew run:
  
  ```
  brew install docker --cask
  ```

You can check the [Docker installation documentation](https://docs.docker.com/engine/install/) for detailed instructions.

- Start Docker Desktop by opening the Docker app using the Finder.

- Go to Settings -> Advanced. Make sure you have ticked the option `Allow the default Docker socket to be used (requires password)`

### Windows

- Install [WSL](https://learn.microsoft.com/en-us/windows/wsl/install)
  Open PowerShell or Windows Command Prompt in administrator mode by right-clicking and selecting "Run as administrator".

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
    Status should be say `Up` and `healthy`.

4. Connect to a mongos router to access the cluster. For example:

    ```
    docker exec -it test01-mongos00 mongosh admin -u root -p percona
    sh.status()
    ```

- There is no need to run the Ansible playbook for the Docker deployments.

### PMM Monitoring

- You can access the PMM Server by opening a web browser at https://127.0.0.1:443. The default credentials are `admin/admin`.
- Grafana renderer is installed and configured in order to be able to export any PMM graphic as a PNG image.

### PBM Backup

- A dedicated `pbm-cli` container is deployed where you can run PBM commands. Example:
  ```
  docker exec -it test01-pbm-cli pbm status
  ```
- You can access the Minio web interface at http://127.0.0.1:9001 to inspect the backup storage/files. The default credentials are `minio/minioadmin`.

### Simulating a workload

- To be able to run test workloads, a YCSB container is created as part of the stack. A sharded `ycsb.usertable` collection is automatically created with `{_id: hashed }` as the shard key. 

To run a YCSB workload:

1. Start a shell session inside the YCSB container
```
docker exec -it test01-ycsb /bin/bash
```

2. Perform initial data load against one of the mongos containers, using the correct credentials and port number.
```
/ycsb/bin/ycsb load mongodb -P /ycsb/workloads/workloada -p mongodb.url="mongodb://root:percona@test01-mongos00:27017/"
```

3. Run the benchmark
```
/ycsb/bin/ycsb run mongodb -s -P /ycsb/workloads/workloada -p operationcount=1500000 -threads 4 -p mongodb.url="mongodb://root:percona@test01-mongos00:27017/"
```

## Cleanup

1. Run terraform to remove all the resources and start from scratch
  ```
  terraform destroy
  ```
