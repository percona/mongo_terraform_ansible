# Deploy MongoDB on Docker with Terraform

This module deploys the full Percona MongoDB stack on Docker containers:

- Percona Server for MongoDB
- Percona Backup for MongoDB
- PMM Client
- PMM Server (with Grafana Renderer)

It can also create:

- MinIO server (with a storage bucket for PBM backups)
- YCSB container (for generating workloads)
- LDAP Server (optional for authentication)

By default it deploys one sharded cluster with 2 shards. Each shard is a 3-node PSA replica set running the latest component versions.

Additional clusters can be defined in a `.tfvars` file. Example:

```
clusters = {
    "cl01" = {
        env_tag               = "test"
        configsvr_count       = 3
        shard_count           = 2
        shardsvr_replicas     = 3
        arbiters_per_replset  = 0
        mongos_count          = 2
    }
    "cl02" = {
        env_tag               = "prod"
        configsvr_count       = 3
        shard_count           = 2
        shardsvr_replicas     = 3
        arbiters_per_replset  = 0
        mongos_count          = 2
    }    
}

replsets = {}

pmm_servers = {
  "pmm-server" = {}
}

minio_servers = {
  "minio" = {}
}

ldap_servers = {}
```

By default, no standalone replica sets are created. To provision one outside a sharded cluster, use a `.tfvars` file like this:

```
clusters = {}

replsets = {
    "rs01" = {
        env_tag      = "test"
        replset_port = 27020
        arbiter_port = 27027
    }
}

pmm_servers = {
  "pmm-server" = {}
}

minio_servers = {
  "minio" = {}
}

ldap_servers = {}
```

If you want only a replica set with no PMM or PBM, use:
```
clusters = {}

replsets = {
    "rs01" = {
        env_tag      = "test"
        enable_pmm = false
        enable_pbm = false
    }
}

pmm_servers = {}

minio_servers = {}

ldap_servers = {}
```

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/downloads) 1.0+
- [Docker](https://docs.docker.com/get-docker/)

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

- Open the `Ubuntu` app from Windows Menu and proceed with the creation of a Linux user and password of your choice.

- [Install Terraform](https://developer.hashicorp.com/terraform/install) inside Linux. Example for Ubuntu:

  ```
  wget -O - https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
  sudo apt update && sudo apt install terraform
  ```

- Install [Docker Desktop on WSL](https://docs.docker.com/desktop/features/wsl/#turn-on-docker-desktop-wsl-2). Depending on your Windows version, Docker Desktop may prompt you to enable WSL 2 during installation.


## Initial Setup

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

1. Create a `tfvars` file with your desired configuration. See the examples above.

    ```
    vi example.tfvars
    ```

2. Run Terraform to create the resources

    ```
    terraform apply -var-file="example.tfvars"
    ``` 

3. Check that all the created containers are running correctly

    ```
    docker ps -a
    ```
    Status should be `Up` and `healthy`.

4. For a sharded cluster, connect to a `mongos` router. Example:

    ```
    docker exec -it cl01-mongos00 mongosh admin -u root -p percona
    sh.status()
    ```

5. For a replica set, connect to any member. Example:

    ```
    docker exec -it rs01-svr0 mongosh admin -u root -p percona
    rs.status()
    ```

- You do not need to run Ansible for Docker-based deployments.

## Expanding Existing Docker Topologies

Supported Docker scale-out changes are handled by Terraform during `terraform apply`:

- Increase `shard_count` to add one or more shards to a sharded cluster.
- Increase `data_nodes_per_replset` to add data-bearing members to a standalone replica set.
- Add a new sharded cluster or standalone replica set to the `.tfvars` file.

Example: add a third shard to `cl01`:

```hcl
clusters = {
  cl01 = {
    shard_count = 3
  }
}
```

Then apply:

```bash
terraform apply -var-file="example.tfvars"
```

Unsupported topology changes are not implemented:

- Reducing `shard_count` or `data_nodes_per_replset`.
- Changing `configsvr_count` after deployment.
- Changing `shardsvr_replicas` on existing shards.
- Changing `arbiters_per_replset` on existing clusters or replica sets.

If using the Go UI, unsupported changes are blocked before Terraform runs.

## Audit Plugin

Both `clusters` and `replsets` support:

- `enable_audit = false` by default
- `audit_filter` with a built-in write-focused default filter for non-system users

Example:

```hcl
replsets = {
  rs01 = {
    env_tag      = "test"
    enable_audit = true
  }
}
```

## PMM Monitoring

- Access PMM at `https://127.0.0.1:8443`. Default credentials: `admin/admin`.

- Grafana renderer is installed so PMM graphs can be exported as PNG images.

## PBM Backup

- A dedicated `pbm-cli` container is deployed for PBM commands. Example:

```
docker exec -it cl01-pbm-cli pbm status
```

- Access the MinIO web console at `http://127.0.0.1:9001`. Default credentials: `minio/minioadmin`.

## Simulating a workload with YCSB

- When `enable_ycsb = true`, a dedicated YCSB container is created.
- The YCSB MongoDB binding is built from a pinned upstream source revision, rather than the legacy 0.17 release archive, to use a modern MongoDB Java driver compatible with PSMDB 8.3.
- For sharded clusters, a sharded `ycsb.usertable` collection is created automatically with `{_id: hashed}` as the shard key.

- To run a YCSB workload:

  1. Start a shell session inside the YCSB container

     ```
     docker exec -it <prefix>-ycsb /bin/bash
     ```

  2. Perform initial data load against one of the mongos containers, using the correct credentials and port number.

     ```
     /ycsb/bin/ycsb load mongodb -P /ycsb/workloads/workloada -p mongodb.url="mongodb://root:percona@cl01-mongos00:27017/"
     ```

  3. Run the benchmark

     ```
     /ycsb/bin/ycsb run mongodb -s -P /ycsb/workloads/workloada -p operationcount=1500000 -threads 4 -p mongodb.url="mongodb://root:percona@cl01-mongos00:27017/"
     ```

## LDAP

- Access the LDAP management interface at `http://127.0.0.1:8080` with `cn=admin,dc=example,dc=org`. Default password: `admin`.

- By default, the `example.org` organization is created. You can pre-create users with Terraform or add them manually in the management UI.

- Create the LDAP users in MongoDB and assign them a role. For example:

  ```
  docker exec -it cl01-mongos00 mongosh admin -u root -p percona
  db.getSiblingDB("$external").createUser( { user: "bob", roles: [ { role: "read", db: "test" } ] } );
  ```

  Then you can authenticate as that user with:
  ```
  mongosh -u bob -p ***** --port 27017 --authenticationMechanism=PLAIN --authenticationDatabase=$external
  ```

## Cleanup

- Remove all resources and start over with:

  ```
  terraform destroy
  ```
