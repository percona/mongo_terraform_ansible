# Optional PSMDB encryption at rest with Vault

Enable **Encryption at rest (PSMDB / Vault)** once in the environment's General
settings. When enabled, every cluster and replica set in that environment uses
the dedicated Vault instance; mixed encrypted/unencrypted topologies are not
supported. PMM is not required. The default is disabled.

Only PSMDB is supported. Community and Enterprise selections are rejected.
For Docker, select a `percona/percona-server-mongodb` image. A sharded cluster's
config servers and shard data nodes are encrypted; arbiters and mongos are not.
MongoDB network TLS is a separate option; the Vault connection always uses TLS.

## Manual configuration

In AWS, GCP, Azure, CHAOS, or Docker `.tfvars`:

```hcl
prefix = "encryptedlab"
vault_encryption = true
clusters = {}
replsets = {
  rs01 = {
    data_nodes_per_replset = 3
    arbiters_per_replset   = 0
  }
  rs02 = {
  }
}
```

For cloud/CHAOS, select `mongodb_distribution = "psmdb"` and a matching
`mongo_release`, then run the normal Terraform and Ansible workflow. `main.yml`,
`add_shard.yml`, `add_replset_member.yml`, and `restart.yml` bootstrap/unseal Vault
before the database tasks. Generated inventories include a `[vault]` group.
An environment-wide `<prefix>_inventory_vault` is also generated for recovery:

```bash
ansible-playbook -i encryptedlab_inventory_vault ../../ansible/vault_server.yml
```

Optional infrastructure variables:

| Target | Settings |
|---|---|
| AWS / GCP / Azure | `vault_type`, `vault_volume_size` |
| CHAOS | `vault_cpu_cores`, `vault_memory_gb`, `vault_volume_size` |
| Docker | `vault_image` (default `hashicorp/vault:1.21.4`) |
| All | `vault_controller_dir` (private recovery directory) |

Native installation pins Vault to `1.21.4`; override the Ansible `vault_version`
extra variable to select another version. Docker requires controller-side
Python 3 and OpenSSL, and bootstraps Vault during Terraform apply. It does not
publish a Vault host port. Encrypted Docker topologies must use the environment
network. MongoDB master keys and Vault tokens are not Terraform variables/state.

Enable encryption only for fresh data directories. The UI rejects changing the
environment-level setting after deployment; migrate or recreate the data to
change encryption mode. New topologies and scale-out nodes inherit the
environment setting. Keep it unchanged when editing manual Terraform
configurations.

### Libvirt

Libvirt continues to provision base VMs for manually inventoried MongoDB hosts.
List only data-bearing hosts in the encrypted topology map:

```hcl
vault_environment = "encryptedlab"
vault_encryption  = true
vault_ip          = "192.168.100.20"
vault_topologies = {
  replset-rs01 = ["db-1", "db-2", "db-3"]
}
```

This adds a dedicated Vault VM and generates
`encryptedlab_inventory_vault.yml`. Merge it with the existing MongoDB inventory:

```bash
ansible-playbook -i inventory.yml -i encryptedlab_inventory_vault.yml ../../ansible/main.yml
```

`vault_encryption` applies to every topology listed in `vault_topologies`.
Use distinct environment identifiers, hostnames, and non-overlapping IPs for
separate Libvirt environments. Do not list arbiters or mongos as encrypted hosts.

## Controller-managed unsealing and recovery

Vault uses persistent file storage, TLS, and a five-share/three-share-threshold
Shamir seal. Initialization writes `init.json` to the controller **before**
unsealing. That file contains the shares and bootstrap root token. It is not
stored on the Vault host. The controller also stores its trust certificate and
one scoped client token per encrypted topology. Directories have mode `0700`,
and secret files have mode `0600`.

Native Vault data is on the dedicated VM's OS disk; Docker uses a named data
volume. Keep Vault VM image/identity settings stable during redeployment.
Replacing a Vault disk requires restoring its stored data and matching recovery
material; unseal shares alone cannot recover deleted master keys.

Default locations:

- UI: `$UI_DATA_DIR/secrets/vault/<environment-id>/`
- Manual native/Libvirt: `ansible/.vault/<platform>/<prefix-or-vault_environment>/`
- Manual Docker: `terraform/docker/.vault/<prefix>/` (`default` without a prefix)

Back up the recovery directory and Vault's persistent storage together. An
initialized Vault without its controller material fails explicitly. An empty
Vault with existing controller material also fails rather than silently creating
new keys. Restoring only the shares does not restore lost MongoDB master keys.

An unexpected Vault restart leaves it sealed. Run framework Restart or the
recovery playbook before restarting encrypted MongoDB nodes. For manual Docker:

```bash
VAULT_CONTAINER=encryptedlab-vault \
VAULT_IMAGE=hashicorp/vault:1.21.4 \
VAULT_CONTROLLER_DIR="$PWD/.vault/encryptedlab" \
VAULT_CREDENTIALS='{"replset-rs01":"encryptedlab-vault-replset-rs01-credentials"}' \
python3 ../../scripts/vault-docker.py bootstrap
```

MongoDB tokens are scoped to each topology's data and metadata paths, plus the
KV engine configuration and token self-renewal endpoints. They are orphan,
periodic 30-day tokens. A native systemd timer renews them daily; Docker renews
them hourly in the Vault container. Root/unseal material is not needed for these
renewals. If a token expires during a long outage, controller bootstrap replaces
it and configuration/restart distributes the replacement to MongoDB nodes.

Secret paths are stable per node. KV v2 retains up to 10,000 versions; PSMDB's
version-limit checks protect older master keys from being silently discarded.

## Lifecycle and checking status

- Reset/redeploy preserves Vault data and controller recovery material.
- UI Docker Restart stops consumers, restarts/unseals Vault, and starts consumers.
- Native Stop stops database services and leaves the key service running.
- Destroy deletes the Vault host/container, stored keys, credential volumes, and
  controller recovery directory. Retained encrypted physical backups cannot be
  restored after their required keys are destroyed.

Check each data-bearing node:

```javascript
db.serverStatus().encryptionAtRest
```

Expect `encryptionEnabled: true` and a Vault path/version in `encryptionKeyId`.
This encrypts MongoDB storage, not audit/process logs, logical exports, or search
indexes.

Encrypted Docker PBM agents receive read-only mounts of the topology Vault
credentials and MongoDB authentication keyfile, so a restore-side mongod can
access the paths in the captured server configuration. Physical restores still
require the corresponding master-key versions to remain in Vault.
