# Deploy MongoDB clusters using Ansible
## Quick guide
1. Create an inventory file
2. Edit the [all variables file](group_vars/all)
3. Run the playbook
```
ansible-playbook main.yml -i inventory.ini --ask-become-pass
```

## Inventory file

- Keep a separate inventory file per environment (for example dev, test, prod).
- If you have more than one cluster per environment, then keep one inventory per cluster as well (for example devrs1, devrs2, devshard1, devshard2).
- On each inventory file, we have to specify groups for each shard's replicaset (name them shardXXXX), as well as the config servers (cfg) and mongos routers (mongos). 
- For each standalone replicaset you should name them rsXXXX.
- You can specify a server in more than one group only for the case of deploying the mongos + config server combination. Any other combinations are currently not supported and cause execution to fail.

- Example of inventory for a sharded cluster:
```
[cfg]
ip-10-0-1-199.ec2.internal mongodb_primary=True
host2
host3

[shard1]
ip-10-0-1-61.ec2.internal mongodb_primary=True
host5
host6

[shard2]
ip-10-0-1-72.ec2.internal mongodb_primary=True
host8
host9

[shard3]
host10

[mongos]
ip-10-0-1-199.ec2.internal
```
- Example of inventory for a single replicaset:
```
[rs1]
host11 mongodb_primary=True
host12
host13
```

The `mongodb_primary` tag will make that server become the primary by giving it higher priority in the replicaset configuration.
Only 1 sharded cluster per inventory is supported at this time.

## Configuration
* The [all variables file](group_vars/all) contains all the user-modifiable parameters. Each of these come with a small description to clarify the purpose, unless it is self-explanatory. 
You should review and modify this file before making the deployment.
 
## Running
* The playbook is meant to handle a deployment from scratch, unless run with some specific tags (e.g. conf). So be extra careful if you are running it against servers that already have data.

- Available tags:
  - backup
    - Deploys & configures the pbm agent
  - monitoring
    - Deploys pmm2 client and registers with a pmm server

* Deploy a replica set or sharded cluster from scratch:
```
ansible-playbook main.yml -i inventory.ini --ask-become-pass 
```
* Add a new shard (e.g. shard3) to an existing cluster:
```
ansible-playbook main.yml -i inventory.ini --ask-become-pass --limit shard3
```
* Deploy skip the monitoring and backup parts
```
ansible-playbook main.yml -i inventory.ini --ask-become-pass --skip-tags monitoring,backup
```

## Cleanup
* If you want cleanup a failed deploy, usually stopping mongod/mongos components and removing the datadir content is enough e.g.
```
service mongos stop; service mongod stop; rm -rf /var/lib/mongo/*
```

## Connecting 
* Connection string example with TLS
```
mongo --tls --tlsCAFile /tmp/test-ca.pem --tlsCertificateKeyFile /tmp/test-client.pem --port 27017 --host ip-10-0-1-199.ec2.internal -u root -p percona
```
* Listing existing backups with TLS
```
pbm list --mongodb-uri "mongodb://pbm:secretpwd@ip-10-0-1-199.ec2.internal:27019/?tls=true&tlsCertificateKeyFile=/tmp/test-server.pem&tlsCAFile=/tmp/test-ca.pem"
```
