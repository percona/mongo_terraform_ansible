# Deploy MongoDB in Docker using Terraform

Deploys the full stack of Percona MongoDB software on Docker containers:

- Percona Server for MongoDB
- Percona Backup for MongoDB
- PMM Client
- PMM Server (with Grafana Renderer)

In addition to this, the following resources are also created:

- MinIO server (with a storage bucket for PBM backups)
- YCSB container (for generating workloads)
- LDAP Server (optional for authentication)

By default we deploy a sharded cluster (2 shards), where each shard is a 3-node PSA Replica Set running the latest versions of every component. 

Additional clusters can be created by customizing the `clusters` variables by creating a `tfvars` file. Examples:

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

By default, no stand-alone replica sets are created. If you want to provision any replica sets not part of a sharded cluster, create a `tfvars` file as follows:

```
clusters = {}

replsets = {
    "rs01" = {
        env_tag      = "test"
        replset_port = 27020
        arbiter_port = 27027
}

pmm_servers = {
  "pmm-server" = {}
}

minio_servers = {
  "minio" = {}
}

ldap_servers = {}
```

If you want just a replica set with no other components, you can use:
```
clusters = {}

replsets = {
    "rs01" = {
        env_tag      = "test"
        enable_pmm = false
        enable_pbm = false
}

pmm_servers = {}

minio_servers = {}

ldap_servers = {}
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

- Open the `Ubuntu` app from Windows Menu and proceed with the creation of a Linux user and password of your choice.

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

- There is no need to run the Ansible playbook for this Docker-based deployments.

## PMM Monitoring

- You can access the PMM Server by opening a web browser at https://127.0.0.1:8443. The default credentials are `admin/admin`.

- Grafana renderer is installed and configured, in order to be able to export any PMM graphic as a PNG image.

## PBM Backup

- A dedicated `pbm-cli` container is deployed where you can run PBM commands. Example:

```
docker exec -it cl01-pbm-cli pbm status
```

- You can access the Minio Server web interface at http://127.0.0.1:9001 to inspect the backup storage/files. The default credentials are `minio/minioadmin`.

## Simulating a workload with YCSB

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

## LDAP

- Connect to the LDAP management interface at http://127.0.0.1:8080 using `cn=admin,dc=example,dc=org`. Default password is `admin`

- By default `example.org` organization is created. You can pre-create some LDAP users with Teerraform or use the management interface to do it manually.

- Create the LDAP users in MongoDB and assign them a role. For example:

  ```
  docker exec -it cl01-mongos00 mongosh admin -u root -p percona
  db.getSiblingDB("$external").createUser( { user: "bob", roles: [ { role: "read", db: "test" } ] } );
  ```

  Then you can authenticate as that user with:
  ```
  mongosh -u bob -p ***** --port 27017 --authenticationMechanism=PLAIN --authenticationDatabase=$external
  ```

## OIDC (with Keycloak)

Percona Server for MongoDB supports OIDC authentication via the `MONGODB-OIDC` mechanism. Keycloak is used as the identity provider. A self-signed TLS certificate is generated directly inside the Keycloak container (using the Keycloak image's built-in OpenSSL), written to a Docker volume that is also mounted into each MongoDB container so the CA cert is automatically trusted.

To enable OIDC, deploy a Keycloak server and set `enable_oidc = true` in your `tfvars` file. Both must share the same Docker network and `pki_certs_volume_name`. Example:

```
keycloak_servers = {
  "keycloak" = {
    env_tag               = "test"
    pki_certs_volume_name = "keycloak-certs"
    oidc_realm            = "percona"
    oidc_client_id        = "mongodb"
    oidc_client_secret    = "mongodb-secret"
    oidc_users            = [
      {
        username   = "alice"
        password   = "secret123"
        email      = "alice@example.org"
        first_name = "Alice"
        last_name  = "Admin"
      }
    ]
  }
}

replsets = {
  "rs01" = {
    env_tag               = "test"
    enable_pmm            = false
    enable_pbm            = false
    enable_oidc           = true
    oidc_issuer           = "https://keycloak:8443/realms/percona"
    oidc_audience         = "mongodb"
    pki_certs_volume_name = "keycloak-certs"
  }
}

pmm_servers  = {}
minio_servers = {}
ldap_servers = {}
clusters     = {}
```

- The self-signed TLS certificate and key for Keycloak are generated by the `hashicorp/tls` Terraform provider. A short-lived Docker init container writes them into the `keycloak-certs` Docker volume. The Keycloak server then starts and serves HTTPS on port 8443 (internal; mapped to port 8444 on the host by default to avoid conflicts with PMM).

- Each MongoDB container mounts the same `keycloak-certs` volume at `/etc/mongo/oidc-certs` (read-only). The `NODE_EXTRA_CA_CERTS=/etc/mongo/oidc-certs/ca.crt` environment variable is set so that mongod trusts the Keycloak CA cert when validating OIDC tokens against `https://keycloak:8443`.

- The Keycloak admin console is accessible at http://127.0.0.1:8080. Default credentials are `admin/admin`.

- Create the OIDC user in MongoDB and assign them a role. For example:

  ```
  docker exec -it rs01-svr0 mongosh admin -u root -p percona
  db.getSiblingDB("$external").createUser( { user: "oidc/alice", roles: [ { role: "read", db: "test" } ] } );
  ```

  The username format is `<authNamePrefix>/<principalName claim value>`. With the defaults, the prefix is `oidc` and the claim is `preferred_username`.

- To authenticate using OIDC, use the device authorization flow. Run mongosh **inside** one of the MongoDB containers — the `NODE_EXTRA_CA_CERTS` env var is already set so mongosh trusts the Keycloak CA:

  ```
  docker exec -it rs01-svr0 mongosh "mongodb://rs01-svr0:27017/?authMechanism=MONGODB-OIDC" \
    --authenticationDatabase '$external'
  ```

  For a sharded cluster, run it against one of the mongos routers:

  ```
  docker exec -it cl01-mongos00 mongosh "mongodb://cl01-mongos00:27017/?authMechanism=MONGODB-OIDC" \
    --authenticationDatabase '$external'
  ```

  mongosh will print output similar to:

  ```
  To sign in, use a web browser to open the page https://keycloak:8443/realms/percona/device and enter the code XXXX-XXXX
  ```

  Since `keycloak` is a Docker container hostname and not resolvable in your browser, open the equivalent URL via localhost instead:
  `http://localhost:8080/realms/percona/device`

  Enter the device code shown, log in as `alice`, and mongosh will automatically complete the authentication.

## Cleanup

- Run terraform to remove all the resources and start from scratch

  ```
  terraform destroy
  ```
