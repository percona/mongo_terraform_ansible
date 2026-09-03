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
- Percona ClusterSync for MongoDB (PCSM), disabled by default

By default it deploys one sharded cluster with 2 shards. Each shard is a 3-node PSA replica set running the latest component versions.

### Minimum `tfvars`

The checked-in [`minimum.tfvars`](./minimum.tfvars) is the smallest standalone
replica-set deployment. It disables PMM, PBM, MinIO, and LDAP so no supporting
containers are required.

```hcl
prefix = "myenv"

clusters = {}

replsets = {
  rs01 = {
    enable_pmm = false
    enable_pbm = false
  }
}

pmm_servers  = {}
minio_servers = {}
ldap_servers  = {}
```

Apply it with `terraform apply -var-file=minimum.tfvars`.

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

- Terraform 1.0+
- Docker Engine or Docker Desktop, running and accessible to the current user

On supported macOS, Debian-family Linux, or RHEL-family Linux controllers, install
both with the repository installer from the root directory:

```bash
./scripts/install-prerequisites.sh --docker
```

macOS requires Homebrew to be installed beforehand. Start Docker Desktop after
installation. On Linux, start a new login session after adding yourself to the
`docker` group. See the root [prerequisites](../../README.md#prerequisites) for
installer scope and limitations.

### Windows

The repository installer does not support Windows. Use WSL and install Terraform
and Docker Desktop manually as described below.

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

## Percona ClusterSync for MongoDB

PCSM is disabled by default. Before enabling it, create a host file readable only by its owner (mode `0600`) using shell-compatible assignments:

```sh
PCSM_SOURCE_URI='mongodb://source-user:source-password@source-host:27017'
PCSM_TARGET_URI='mongodb://target-user:target-password@target-host:27017'
```

Pass only its path through Terraform:

```hcl
enable_pcsm      = true
pcsm_env_file    = "/absolute/path/to/pcsm.env"
pcsm_source_kind = "cluster"
pcsm_source_name = "cl01"
pcsm_target_kind = "cluster"
pcsm_target_name = "cl02"
```

`pcsm_source_kind` and `pcsm_target_kind` must both be `cluster` or both be `replset`. The names must be different keys in the corresponding `clusters` or `replsets` map. Terraform records these nonsecret selectors as Docker labels only; it does not generate an Ansible inventory because Docker configures MongoDB directly.

Terraform mounts the file read-only and never reads its contents, so the URIs are not stored in Terraform state. One `<prefix>-pcsm` container is attached to the environment network after all MongoDB modules complete. It publishes no API port and defaults to image `percona/percona-clustersync-mongodb:0.9.0`, 2 CPUs, and 1024 MiB of memory. The host path must be shared with Docker Desktop where applicable.

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

- Access the LDAP management interface at `http://127.0.0.1:8080` with `cn=admin,dc=example,dc=com`. Default password: `admin`.

- By default, the `example.com` organization is created. You can pre-create users with Terraform or add them manually in the management UI.

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
